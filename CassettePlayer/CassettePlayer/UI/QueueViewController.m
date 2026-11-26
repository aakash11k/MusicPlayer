#import "QueueViewController.h"
#import "PlaybackManager.h"

@implementation QueueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Up Next Queue";
    self.tableView.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(closeSelf)];

    [[NSNotificationCenter defaultCenter] addObserver:self.tableView
                                             selector:@selector(reloadData)
                                                 name:PlaybackDidUpdateQueueNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (void)closeSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [PlaybackManager sharedManager].queue.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"QueueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }

    PlaybackManager *pm = [PlaybackManager sharedManager];
    TrackItem *t = pm.queue[indexPath.row];
    BOOL isCurrent = (indexPath.row == pm.currentIndex);

    cell.textLabel.text = isCurrent ? [NSString stringWithFormat:@"▶ %@", t.title] : t.title;
    cell.textLabel.textColor = isCurrent ? [UIColor colorWithRed:0.92 green:0.46 blue:0.16 alpha:1.0] : [UIColor whiteColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", t.artist, [t formattedQualityBadge]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[PlaybackManager sharedManager] playQueueIndex:indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row != [PlaybackManager sharedManager].currentIndex;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [[PlaybackManager sharedManager] removeTrackFromQueueAtIndex:indexPath.row];
    }
}

@end
