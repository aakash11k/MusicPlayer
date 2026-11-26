#import "WiFiUploadServer.h"
#import "MusicLibrary.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>

@interface WiFiUploadServer () {
    int _listenSocket;
    dispatch_queue_t _serverQueue;
}
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, copy, readwrite) NSString *serverURLString;
@end

@implementation WiFiUploadServer

+ (instancetype)sharedServer {
    static WiFiUploadServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WiFiUploadServer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenSocket = -1;
        _serverQueue = dispatch_queue_create("com.cassetteplayer.wifi", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (BOOL)startWithPort:(uint16_t)port {
    if (self.isRunning) return YES;

    _listenSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_listenSocket < 0) return NO;

    int yes = 1;
    setsockopt(_listenSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(_listenSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_listenSocket);
        _listenSocket = -1;
        return NO;
    }

    if (listen(_listenSocket, 8) < 0) {
        close(_listenSocket);
        _listenSocket = -1;
        return NO;
    }

    self.isRunning = YES;
    NSString *ip = [self localWiFiIPAddress] ?: @"<iPhone-IP>";
    self.serverURLString = [NSString stringWithFormat:@"http://%@:%u", ip, (unsigned int)port];

    dispatch_async(_serverQueue, ^{
        while (self.isRunning && self->_listenSocket >= 0) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSock = accept(self->_listenSocket, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientSock >= 0) {
                dispatch_async(self->_serverQueue, ^{
                    [self handleClientSocket:clientSock];
                });
            }
        }
    });

    return YES;
}

- (void)stop {
    self.isRunning = NO;
    if (_listenSocket >= 0) {
        close(_listenSocket);
        _listenSocket = -1;
    }
    self.serverURLString = nil;
}

- (void)handleClientSocket:(int)sock {
    // Read HTTP headers first
    NSMutableData *headerData = [NSMutableData data];
    char buf[4096];
    NSRange headerEndRange = NSMakeRange(NSNotFound, 0);

    while (headerData.length < 65536) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [headerData appendBytes:buf length:n];
        NSData *crlf2 = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        headerEndRange = [headerData rangeOfData:crlf2 options:0 range:NSMakeRange(0, headerData.length)];
        if (headerEndRange.location != NSNotFound) break;
    }

    if (headerEndRange.location == NSNotFound) {
        close(sock);
        return;
    }

    NSData *rawHeaders = [headerData subdataWithRange:NSMakeRange(0, headerEndRange.location)];
    NSString *headerStr = [[NSString alloc] initWithData:rawHeaders encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [headerStr componentsSeparatedByString:@"\r\n"];
    NSString *requestLine = lines.firstObject ?: @"";

    long long contentLength = 0;
    NSString *xFilename = nil;
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *k = [[line substringToIndex:colon.location] lowercaseString];
            NSString *v = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([k isEqualToString:@"content-length"]) {
                contentLength = [v longLongValue];
            } else if ([k isEqualToString:@"x-filename"]) {
                xFilename = [v stringByRemovingPercentEncoding];
            }
        }
    }

    NSUInteger bodyStart = headerEndRange.location + headerEndRange.length;
    NSData *initialBody = [headerData subdataWithRange:NSMakeRange(bodyStart, headerData.length - bodyStart)];

    if ([requestLine hasPrefix:@"GET / "]) {
        NSString *html = [self uploadPageHTML];
        NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];
        NSString *resp = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)htmlData.length];
        send(sock, resp.UTF8String, strlen(resp.UTF8String), 0);
        send(sock, htmlData.bytes, htmlData.length, 0);
    } else if ([requestLine hasPrefix:@"POST /upload"]) {
        NSString *safeName = [xFilename.lastPathComponent stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        if (safeName.length == 0) {
            safeName = [NSString stringWithFormat:@"track_%ld.flac", (long)[[NSDate date] timeIntervalSince1970]];
        }
        NSString *destPath = [[[MusicLibrary sharedLibrary] documentsMusicDirectory] stringByAppendingPathComponent:safeName];

        // Stream directly to file so large 24-bit FLACs don't exhaust iPhone 4S RAM
        NSOutputStream *outStream = [NSOutputStream outputStreamToFileAtPath:destPath append:NO];
        [outStream open];

        long long received = 0;
        if (initialBody.length > 0) {
            [outStream write:initialBody.bytes maxLength:initialBody.length];
            received += initialBody.length;
        }

        while (received < contentLength) {
            ssize_t n = recv(sock, buf, sizeof(buf), 0);
            if (n <= 0) break;
            [outStream write:(const uint8_t *)buf maxLength:(NSUInteger)n];
            received += n;
        }
        [outStream close];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[MusicLibrary sharedLibrary] reloadLibrary];
        });

        NSString *json = [NSString stringWithFormat:@"{\"ok\":true,\"filename\":\"%@\",\"bytes\":%lld}", safeName, received];
        NSString *resp = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@", (unsigned long)json.length, json];
        send(sock, resp.UTF8String, strlen(resp.UTF8String), 0);
    } else {
        const char *notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found";
        send(sock, notFound, strlen(notFound), 0);
    }

    close(sock);
}

- (NSString *)localWiFiIPAddress {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr && temp->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
                if ([name isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    return address;
}

- (NSString *)uploadPageHTML {
    return @"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>Cassette Lossless Uploader</title>"
    "<style>body{font-family:-apple-system,sans-serif;background:#141416;color:#f5f2eb;max-width:560px;margin:40px auto;padding:20px}"
    "h1{color:#ff9f43;margin-bottom:6px}p{color:#a8a49c}label{display:block;border:2px dashed #ff9f43;border-radius:14px;padding:40px 20px;text-align:center;cursor:pointer;background:#1e1e22}"
    "#log{margin-top:20px;font-size:14px;line-height:1.6}</style></head><body>"
    "<h1>Cassette Lossless Deck</h1><p>Drop your <b>.FLAC</b> or <b>.M4A (ALAC)</b> songs below to transfer directly to your iPhone 4S.</p>"
    "<label id='drop'><input id='f' type='file' multiple accept='.flac,.m4a,.alac,.caf,.wav,.aiff' style='display:none'>Tap or Drag & Drop Lossless Audio Files Here</label>"
    "<div id='log'></div><script>"
    "const inp=document.getElementById('f'),log=document.getElementById('log'),drop=document.getElementById('drop');"
    "async function sendFiles(files){for(const file of files){const p=document.createElement('div');p.textContent='Uploading '+file.name+'...';log.prepend(p);"
    "const r=await fetch('/upload',{method:'POST',headers:{'X-Filename':encodeURIComponent(file.name)},body:file});"
    "p.textContent=r.ok?'✓ Uploaded '+file.name:'✗ Failed '+file.name;}}"
    "inp.onchange=()=>sendFiles(inp.files);"
    "drop.ondragover=e=>{e.preventDefault();drop.style.background='#28282e'};"
    "drop.ondragleave=()=>{drop.style.background='#1e1e22'};"
    "drop.ondrop=e=>{e.preventDefault();drop.style.background='#1e1e22';sendFiles(e.dataTransfer.files);};"
    "</script></body></html>";
}

@end
