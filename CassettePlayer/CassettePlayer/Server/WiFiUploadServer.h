#import <Foundation/Foundation.h>

@interface WiFiUploadServer : NSObject

@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, copy, readonly) NSString *serverURLString;

+ (instancetype)sharedServer;

- (BOOL)startWithPort:(uint16_t)port;
- (void)stop;

@end
