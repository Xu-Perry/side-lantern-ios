#import "ComputerFilesViewController.h"
#import "ComputerFilesClient.h"
#import "TemporaryHost.h"

#define ComputerFilesText(key) NSLocalizedStringFromTable(key, @"ComputerFiles", nil)

static BOOL isNonemptyString(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] != 0;
}

static BOOL isDirectory(NSDictionary* item) {
    return [@"directory" isEqual:item[@"kind"]];
}

static BOOL isDrive(NSDictionary* root) {
    return [@"drive" isEqual:root[@"kind"]] || (root[@"kind"] == nil && [root[@"id"] hasPrefix:@"drive-"]);
}

@implementation ComputerFilesViewController {
    TemporaryHost* _host;
    ComputerFilesClient* _client;
    NSString* _root;
    NSString* _path;
    NSUInteger _chunkSize;
    NSArray<NSDictionary*>* _items;
    NSNumber* _nextOffset;
    BOOL _truncated;
    BOOL _loading;
    NSString* _pageError;
    NSUUID* _downloadID;
    NSNumberFormatter* _progressFormatter;
}

- (instancetype)initWithHost:(TemporaryHost*)host {
    return [self initWithHost:host root:nil path:@"" title:ComputerFilesText(@"Browse Computer Files") chunkSize:0];
}

- (instancetype)initWithHost:(TemporaryHost*)host
                       root:(NSString*)root
                       path:(NSString*)path
                      title:(NSString*)title
                  chunkSize:(NSUInteger)chunkSize {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _host = host;
        _client = [[ComputerFilesClient alloc] initWithHost:host];
        _root = [root copy];
        _path = [path copy];
        _chunkSize = chunkSize;
        _items = @[];
        self.title = title;
        if (_root == nil) {
            self.navigationItem.prompt = host.name;
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                                target:self
                                                                                                action:@selector(closeBrowser)];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ComputerFile"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reloadItems) forControlEvents:UIControlEventValueChanged];
    [self reloadItems];
}

- (void)dealloc {
    [_client cancel];
}

- (void)closeBrowser {
    [_client cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reloadItems {
    [self loadItemsFromOffset:@0];
}

- (void)loadItemsFromOffset:(NSNumber*)offset {
    if (_loading || _downloadID) {
        [self.refreshControl endRefreshing];
        return;
    }
    _loading = YES;
    _pageError = nil;
    BOOL append = offset.unsignedLongLongValue > 0;
    if (_items.count == 0) {
        [self showStatus:ComputerFilesText(@"Loading…") loading:YES retry:NO];
    }
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    ComputerFilesJSONCompletion completed = ^(NSDictionary* response, NSError* error) {
        ComputerFilesViewController* self = weakSelf;
        if (self == nil) {
            return;
        }
        self->_loading = NO;
        [self.refreshControl endRefreshing];

        if (error) {
            [self showListError:[self messageForError:error] keepItems:append];
        } else if (self->_root == nil) {
            [self showDrives:response];
        } else {
            [self showDirectory:response afterOffset:offset];
        }
        [self.tableView reloadData];
    };
    if (_root) {
        [_client listRoot:_root path:_path offset:offset completion:completed];
    } else {
        [_client loadDrives:completed];
    }
}

- (void)showDrives:(NSDictionary*)response {
    if (![@1 isEqual:response[@"version"]] || ![response[@"roots"] isKindOfClass:[NSArray class]] ||
        ![response[@"enabled"] isKindOfClass:[NSNumber class]] ||
        ![response[@"download_chunk_bytes"] isKindOfClass:[NSNumber class]] ||
        [response[@"download_chunk_bytes"] longLongValue] <= 0) {
        [self showListError:ComputerFilesText(@"The computer returned an unexpected response.") keepItems:NO];
        return;
    }
    NSMutableArray<NSDictionary*>* roots = [NSMutableArray array];
    for (id root in response[@"roots"]) {
        if ([root isKindOfClass:[NSDictionary class]] && isNonemptyString(root[@"id"]) && isNonemptyString(root[@"label"])) {
            [roots addObject:root];
        }
    }
    [roots sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        if (isDrive(a) != isDrive(b)) {
            return isDrive(a) ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"label"] localizedStandardCompare:b[@"label"]];
    }];
    _chunkSize = [response[@"download_chunk_bytes"] unsignedIntegerValue];
    _items = roots;
    self.tableView.backgroundView = nil;
    if (![response[@"enabled"] boolValue]) {
        [self showListError:ComputerFilesText(@"No drives are available on this computer.") keepItems:NO];
    } else if (_items.count == 0) {
        [self showStatus:ComputerFilesText(@"No drives are available on this computer.") loading:NO retry:YES];
    }
}

- (void)showDirectory:(NSDictionary*)response afterOffset:(NSNumber*)offset {
    id entries = response[@"entries"];
    id next = response[@"next_offset"];
    if (![entries isKindOfClass:[NSArray class]] ||
        (next != [NSNull null] && (![next isKindOfClass:[NSNumber class]] || [next compare:offset] != NSOrderedDescending)) ||
        ![response[@"truncated"] isKindOfClass:[NSNumber class]]) {
        [self showListError:ComputerFilesText(@"The computer returned an unexpected response.") keepItems:offset.unsignedLongLongValue > 0];
        return;
    }
    NSMutableArray<NSDictionary*>* items = offset.unsignedLongLongValue > 0 ? [_items mutableCopy] : [NSMutableArray array];
    for (id item in entries) {
        if (![item isKindOfClass:[NSDictionary class]] || !ComputerFilesIsValidEntryName(item[@"name"])) {
            continue;
        }
        if (isDirectory(item) || ([@"file" isEqual:item[@"kind"]] && [item[@"size"] isKindOfClass:[NSNumber class]] &&
                                  [item[@"size"] longLongValue] >= 0 && isNonemptyString(item[@"version"]))) {
            [items addObject:item];
        }
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        if (isDirectory(a) != isDirectory(b)) {
            return isDirectory(a) ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    _items = items;
    _nextOffset = next == [NSNull null] ? nil : next;
    _truncated = [response[@"truncated"] boolValue];
    self.tableView.backgroundView = nil;
    if (_items.count == 0 && _nextOffset == nil) {
        [self showStatus:ComputerFilesText(@"This folder is empty.") loading:NO retry:NO];
    }
}

- (void)showStatus:(NSString*)message loading:(BOOL)loading retry:(BOOL)retry {
    UIView* background = [[UIView alloc] init];
    UILabel* label = [[UILabel alloc] init];
    label.text = message;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;

    UIStackView* stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    if (loading) {
        UIActivityIndicatorView* spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        [stack addArrangedSubview:spinner];
    }
    [stack addArrangedSubview:label];
    if (retry) {
        UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:ComputerFilesText(@"Try Again") forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [button addTarget:self action:@selector(reloadItems) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }

    [background addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-24],
        [label.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor],
    ]];
    self.tableView.backgroundView = background;
    if (!loading && self.view.window) {
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, label);
    }
}

- (void)showListError:(NSString*)message keepItems:(BOOL)keepItems {
    if (keepItems && _items.count != 0) {
        _pageError = message;
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
        return;
    }
    _items = @[];
    _nextOffset = nil;
    _truncated = NO;
    [self showStatus:message loading:NO retry:YES];
}

- (NSString*)messageForError:(NSError*)error {
    if ([error.domain isEqualToString:ComputerFilesErrorDomain]) {
        switch (error.code) {
            case 401:
            case 403:
                return ComputerFilesText(@"The computer denied access.");
            case 404:
                return _root ? ComputerFilesText(@"This file or folder is no longer available.")
                             : ComputerFilesText(@"This computer does not support file browsing.");
            case 409:
                return ComputerFilesText(@"The file changed on the computer. Refresh the folder and try again.");
            case ComputerFilesErrorCannotStore:
                return ComputerFilesText(@"The file could not be saved on this device.");
            default:
                return ComputerFilesText(@"The computer returned an unexpected response.");
        }
    }
    if ([error.domain isEqualToString:NSURLErrorDomain] &&
        (error.code == NSURLErrorCancelled || error.code == NSURLErrorUserCancelledAuthentication ||
         (error.code <= NSURLErrorSecureConnectionFailed && error.code >= NSURLErrorClientCertificateRequired))) {
        return ComputerFilesText(@"A secure connection to the paired computer could not be verified.");
    }
    return ComputerFilesText(@"Could not reach the computer.");
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count + (_nextOffset ? 1 : 0);
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    if (_root == nil && _items.count != 0) {
        return isDrive(_items.lastObject) ? ComputerFilesText(@"Drives") : ComputerFilesText(@"Drives and Shortcuts");
    }
    return nil;
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    if (_pageError) {
        return _pageError;
    }
    return _truncated ? ComputerFilesText(@"This folder contains more items than can be shown.") : nil;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ComputerFile" forIndexPath:indexPath];
    UIListContentConfiguration* content = [UIListContentConfiguration subtitleCellConfiguration];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityHint = nil;
    if (indexPath.row == _items.count) {
        content.text = _loading ? ComputerFilesText(@"Loading…") : ComputerFilesText(@"Load More");
        content.textProperties.color = self.view.tintColor;
    } else {
        NSDictionary* item = _items[indexPath.row];
        if (_root == nil || isDirectory(item)) {
            content.text = _root == nil ? item[@"label"] : item[@"name"];
            content.image = [UIImage systemImageNamed:_root == nil && isDrive(item) ? @"internaldrive" : @"folder"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            content.text = item[@"name"];
            NSString* size = [NSByteCountFormatter stringFromByteCount:[item[@"size"] longLongValue]
                                                            countStyle:NSByteCountFormatterCountStyleFile];
            NSNumber* modified = item[@"modified_unix_ms"];
            if ([modified isKindOfClass:[NSNumber class]]) {
                NSDate* date = [NSDate dateWithTimeIntervalSince1970:modified.doubleValue / 1000.0];
                NSString* modifiedDate = [NSDateFormatter localizedStringFromDate:date
                                                                        dateStyle:NSDateFormatterShortStyle
                                                                        timeStyle:NSDateFormatterShortStyle];
                content.secondaryText = [NSString stringWithFormat:@"%@ · %@", size, modifiedDate];
            } else {
                content.secondaryText = size;
            }
            content.image = [UIImage systemImageNamed:@"doc"];
            UIImageView* icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"]];
            icon.accessibilityElementsHidden = YES;
            cell.accessoryView = icon;
            cell.accessibilityHint = ComputerFilesText(@"Downloads this file.");
        }
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_loading || _downloadID) {
        return;
    }
    if (indexPath.row == _items.count) {
        [self loadItemsFromOffset:_nextOffset];
        return;
    }

    NSDictionary* item = _items[indexPath.row];
    NSString* name = item[@"name"];
    NSString* path = _path.length ? [NSString stringWithFormat:@"%@/%@", _path, name] : name;
    if (_root == nil || isDirectory(item)) {
        ComputerFilesViewController* folder = [[ComputerFilesViewController alloc] initWithHost:_host
                                                                                          root:_root ?: item[@"id"]
                                                                                          path:_root ? path : @""
                                                                                         title:_root ? name : item[@"label"]
                                                                                     chunkSize:_chunkSize];
        [self.navigationController pushViewController:folder animated:YES];
    } else {
        UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
        [self downloadItem:item path:path sourceView:cell];
    }
}

- (void)downloadItem:(NSDictionary*)item path:(NSString*)path sourceView:(UIView*)sourceView {
    NSString* name = item[@"name"];
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:ComputerFilesText(@"Downloading…")
                                                                  message:name preferredStyle:UIAlertControllerStyleAlert];
    NSUUID* downloadID = [NSUUID UUID];
    _downloadID = downloadID;
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:ComputerFilesText(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action) {
        ComputerFilesViewController* self = weakSelf;
        if (self && self->_downloadID == downloadID) {
            self->_downloadID = nil;
            [self->_client cancel];
        }
    }]];
    [self presentViewController:alert animated:YES completion:^{
        ComputerFilesViewController* self = weakSelf;
        if (self == nil || self->_downloadID != downloadID) {
            return;
        }
        [self->_client downloadRoot:self->_root path:path fileName:name size:[item[@"size"] unsignedLongLongValue]
                            version:item[@"version"] chunkSize:self->_chunkSize progress:^(double fraction) {
            ComputerFilesViewController* self = weakSelf;
            if (self && self->_downloadID == downloadID) {
                if (self->_progressFormatter == nil) {
                    self->_progressFormatter = [[NSNumberFormatter alloc] init];
                    self->_progressFormatter.numberStyle = NSNumberFormatterPercentStyle;
                }
                alert.message = [NSString stringWithFormat:@"%@\n%@", name, [self->_progressFormatter stringFromNumber:@(fraction)]];
            }
        } completion:^(NSURL* fileURL, NSError* error) {
            ComputerFilesViewController* self = weakSelf;
            if (self == nil || self->_downloadID != downloadID || self.view.window == nil) {
                [ComputerFilesClient removeDownloadAtURL:fileURL];
                return;
            }
            self->_downloadID = nil;
            [alert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showDownloadError:error];
                } else {
                    [self exportFile:fileURL sourceView:sourceView];
                }
            }];
        }];
    }];
}

- (void)showDownloadError:(NSError*)error {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:ComputerFilesText(@"Download Failed")
                                                                  message:[self messageForError:error]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:ComputerFilesText(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportFile:(NSURL*)fileURL sourceView:(UIView*)sourceView {
    if (self.view.window == nil || self.presentedViewController) {
        [ComputerFilesClient removeDownloadAtURL:fileURL];
        return;
    }
    UIActivityViewController* share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    UIPopoverPresentationController* popover = share.popoverPresentationController;
    popover.sourceView = self.view;
    popover.sourceRect = sourceView.window ? [sourceView convertRect:sourceView.bounds toView:self.view]
                                          : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    share.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray* returnedItems, NSError* activityError) {
        [ComputerFilesClient removeDownloadAtURL:fileURL];
    };
    [self presentViewController:share animated:YES completion:nil];
}

@end
