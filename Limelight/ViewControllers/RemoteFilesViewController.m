#import "RemoteFilesViewController.h"
#import "FileTransferManager.h"

static NSString *RFText(NSString *key) { return NSLocalizedStringFromTable(key, @"FileTransfer", nil); }
static NSString *RFError(NSError *error) {
    if (![error.domain isEqualToString:FileTransferErrorDomain]) return error.localizedDescription;
    NSString *key = [@"error." stringByAppendingString:error.userInfo[@"reason"] ?: @"request_failed"];
    NSString *text = RFText(key); return [text isEqualToString:key] ? RFText(@"error.request_failed") : text;
}

@interface RemoteFilesViewController () <UITableViewDataSource, UITableViewDelegate>
@end
@implementation RemoteFilesViewController {
    FileTransferManager *_manager; NSArray<FileTransferRoot *> *_roots; FileTransferRoot *_root;
    UITableView *_rootTable, *_fileTable; UIView *_filesContainer, *_toolbar;
    UILabel *_empty; UIButton *_pathButton, *_download; UIStackView *_workspace;
    NSMutableArray<FileTransferEntry *> *_entries; NSMutableSet<NSString *> *_selected;
    NSString *_path; NSNumber *_nextOffset; NSUInteger _generation; BOOL _loading, _wide, _truncated;
    UIRefreshControl *_refresh;
}
- (instancetype)initWithManager:(FileTransferManager *)manager {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _manager = manager; _roots = manager.capabilities.roots ?: @[]; _entries = [NSMutableArray array]; _selected = [NSMutableSet set]; _path = @"";
    } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = RFText(@"browse_title"); self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.accessibilityIdentifier = @"file-transfer-browser"; self.edgesForExtendedLayout = UIRectEdgeNone;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:RFText(@"select_all") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init]; [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColor.systemBackgroundColor; appearance.titleTextAttributes = @{NSForegroundColorAttributeName:UIColor.labelColor};
    self.navigationController.navigationBar.standardAppearance = appearance; self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance; self.navigationController.navigationBar.tintColor = UIColor.labelColor;
    _rootTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _rootTable.delegate = self; _rootTable.dataSource = self;
    _rootTable.accessibilityIdentifier = @"file-transfer-roots"; _rootTable.rowHeight = 64; _rootTable.tableFooterView = [[UIView alloc] init];
    _fileTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _fileTable.delegate = self; _fileTable.dataSource = self;
    _fileTable.accessibilityIdentifier = @"file-transfer-directory"; _fileTable.rowHeight = UITableViewAutomaticDimension; _fileTable.estimatedRowHeight = 70;
    _fileTable.tableFooterView = [[UIView alloc] init]; _fileTable.allowsMultipleSelection = NO;
    _refresh = [[UIRefreshControl alloc] init]; [_refresh addTarget:self action:@selector(reloadDirectory) forControlEvents:UIControlEventValueChanged]; _fileTable.refreshControl = _refresh;
    _empty = [[UILabel alloc] init]; _empty.numberOfLines = 0; _empty.textAlignment = NSTextAlignmentCenter; _empty.textColor = UIColor.secondaryLabelColor;
    _empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; _fileTable.backgroundView = _empty;
    _filesContainer = [[UIView alloc] init];
    _pathButton = [UIButton buttonWithType:UIButtonTypeSystem]; _pathButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    _pathButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle; _pathButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    [_pathButton setImage:[UIImage systemImageNamed:@"arrow.up"] forState:UIControlStateNormal]; [_pathButton addTarget:self action:@selector(goUp) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[_pathButton, _fileTable]) { view.translatesAutoresizingMaskIntoConstraints = NO; [_filesContainer addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[[_pathButton.topAnchor constraintEqualToAnchor:_filesContainer.topAnchor constant:6],
        [_pathButton.leadingAnchor constraintEqualToAnchor:_filesContainer.leadingAnchor constant:16], [_pathButton.trailingAnchor constraintEqualToAnchor:_filesContainer.trailingAnchor constant:-16],
        [_pathButton.heightAnchor constraintEqualToConstant:44], [_fileTable.topAnchor constraintEqualToAnchor:_pathButton.bottomAnchor constant:4],
        [_fileTable.leadingAnchor constraintEqualToAnchor:_filesContainer.leadingAnchor], [_fileTable.trailingAnchor constraintEqualToAnchor:_filesContainer.trailingAnchor], [_fileTable.bottomAnchor constraintEqualToAnchor:_filesContainer.bottomAnchor]]];
    _workspace = [[UIStackView alloc] initWithArrangedSubviews:@[_rootTable, _filesContainer]]; _workspace.axis = UILayoutConstraintAxisHorizontal; _workspace.spacing = 1;
    _workspace.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:_workspace];
    _toolbar = [[UIView alloc] init]; _toolbar.backgroundColor = UIColor.secondarySystemBackgroundColor; _toolbar.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:_toolbar];
    _download = [UIButton buttonWithType:UIButtonTypeSystem]; _download.configuration = UIButtonConfiguration.filledButtonConfiguration;
    _download.translatesAutoresizingMaskIntoConstraints = NO; _download.accessibilityIdentifier = @"file-transfer-download-selection";
    [_download addTarget:self action:@selector(downloadSelected) forControlEvents:UIControlEventTouchUpInside]; [_toolbar addSubview:_download];
    [NSLayoutConstraint activateConstraints:@[[_workspace.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor], [_workspace.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_workspace.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [_workspace.bottomAnchor constraintEqualToAnchor:_toolbar.topAnchor],
        [_toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [_toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [_toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_download.topAnchor constraintEqualToAnchor:_toolbar.topAnchor constant:10], [_download.bottomAnchor constraintEqualToAnchor:_toolbar.bottomAnchor constant:-10],
        [_download.leadingAnchor constraintEqualToAnchor:_toolbar.safeAreaLayoutGuide.leadingAnchor constant:20], [_download.trailingAnchor constraintEqualToAnchor:_toolbar.safeAreaLayoutGuide.trailingAnchor constant:-20], [_download.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    [self updateControls];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; BOOL wide = self.view.safeAreaLayoutGuide.layoutFrame.size.width >= 700;
    if (_wide != wide || !_workspace.accessibilityIdentifier) {
        _wide = wide; _workspace.accessibilityIdentifier = wide ? @"file-transfer-wide-browser" : @"file-transfer-compact-browser";
        for (NSLayoutConstraint *constraint in _rootTable.constraints.copy) if ([constraint.identifier isEqualToString:@"share-width"]) [_rootTable removeConstraint:constraint];
        if (wide) { NSLayoutConstraint *width = [_rootTable.widthAnchor constraintEqualToConstant:230]; width.identifier = @"share-width"; width.active = YES; }
        [self updateControls];
    }
}
- (void)updateControls {
    _rootTable.hidden = !_wide && _root != nil; _filesContainer.hidden = !_wide && _root == nil;
    [_pathButton setTitle:_root ? [NSString stringWithFormat:@"  %@%@", _root.label, _path.length ? [@" / " stringByAppendingString:_path] : @""] : RFText(@"choose_share") forState:UIControlStateNormal];
    _pathButton.enabled = _root && (_path.length > 0 || !_wide);
    [_download setTitle:[NSString stringWithFormat:RFText(@"download_count"), (unsigned long)_selected.count] forState:UIControlStateNormal];
    _download.enabled = _selected.count > 0; _toolbar.hidden = _root == nil;
    self.navigationItem.rightBarButtonItem.enabled = _root != nil && !_loading;
    _pathButton.hidden = _root == nil;
    _empty.text = !_root ? (_roots.count ? RFText(@"choose_share") : RFText(@"no_shares")) : _loading && _entries.count == 0 ? RFText(@"loading") : _entries.count == 0 ? RFText(@"empty_directory") : @"";
    if (_roots.count == 0) { UILabel *label = [[UILabel alloc] init]; label.text = RFText(@"no_shares"); label.numberOfLines = 0; label.textColor = UIColor.secondaryLabelColor; label.textAlignment = NSTextAlignmentCenter; _rootTable.backgroundView = label; }
    [_rootTable reloadData]; [_fileTable reloadData];
}
- (void)reloadDirectory {
    if (!_root) { [_refresh endRefreshing]; return; }
    _generation++; _loading = NO; [_entries removeAllObjects]; [_selected removeAllObjects]; _nextOffset = nil; _truncated = NO;
    [self loadPage:nil];
}
- (void)loadPage:(NSNumber *)offset {
    if (_loading || !_root) return;
    _loading = YES; [self updateControls]; NSUInteger generation = _generation; __weak typeof(self) weakSelf = self;
    [_manager listRoot:_root.identifier path:_path offset:offset completion:^(FileTransferListing *listing, NSError *error) {
        RemoteFilesViewController *controller = weakSelf; if (!controller || generation != controller->_generation) return;
        controller->_loading = NO; [controller->_refresh endRefreshing];
        if (error) { [controller updateControls]; controller->_empty.text = RFError(error); return; }
        if (listing.nextOffset && listing.nextOffset.unsignedLongLongValue <= offset.unsignedLongLongValue) {
            [controller updateControls]; controller->_empty.text = RFText(@"error.invalid_response"); return;
        }
        NSMutableSet *existing = [NSMutableSet set]; for (FileTransferEntry *entry in controller->_entries) [existing addObject:entry.name];
        for (FileTransferEntry *entry in listing.entries) if (![existing containsObject:entry.name]) [controller->_entries addObject:entry];
        [controller->_entries sortUsingComparator:^NSComparisonResult(FileTransferEntry *a, FileTransferEntry *b) {
            if (a.directory != b.directory) return a.directory ? NSOrderedAscending : NSOrderedDescending;
            return [a.name localizedStandardCompare:b.name];
        }];
        controller->_nextOffset = listing.nextOffset; controller->_truncated = listing.truncated;
        [controller updateControls];
    }];
}
- (void)goUp {
    if (_path.length) { _path = [_path stringByDeletingLastPathComponent]; [self reloadDirectory]; }
    else if (!_wide) { _root = nil; _generation++; _loading = NO; [_selected removeAllObjects]; [self updateControls]; }
}
- (void)selectAll {
    NSUInteger files = 0; for (FileTransferEntry *entry in _entries) if (!entry.directory) files++;
    if (_selected.count == files) [_selected removeAllObjects]; else for (FileTransferEntry *entry in _entries) if (!entry.directory) [_selected addObject:entry.name];
    [self updateControls];
}
- (void)downloadSelected {
    for (FileTransferEntry *entry in _entries) if ([_selected containsObject:entry.name]) {
        [_manager enqueueDownload:entry root:_root.identifier path:_path.length ? [_path stringByAppendingPathComponent:entry.name] : entry.name];
    }
    [self.navigationController popViewControllerAnimated:YES];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return tableView == _rootTable ? _roots.count : _entries.count + (_nextOffset || _truncated ? 1 : 0); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return tableView == _rootTable ? RFText(@"shares") : nil; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"file"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"file"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor; cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.tintColor = UIColor.systemBlueColor; cell.detailTextLabel.text = nil; cell.accessoryType = UITableViewCellAccessoryNone;
    if (tableView == _rootTable) {
        FileTransferRoot *root = _roots[indexPath.row]; cell.textLabel.text = root.label;
        cell.imageView.image = [UIImage systemImageNamed:[root.label containsString:@":"] ? @"internaldrive" : @"folder.fill"];
        cell.accessoryType = [root.identifier isEqualToString:_root.identifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    } else if ((NSUInteger)indexPath.row >= _entries.count) {
        cell.textLabel.text = RFText(_nextOffset ? @"load_more" : @"directory_truncated"); cell.imageView.image = nil;
    } else {
        FileTransferEntry *entry = _entries[indexPath.row]; cell.textLabel.text = entry.name;
        cell.imageView.image = [UIImage systemImageNamed:entry.directory ? @"folder.fill" : @"doc"];
        if (entry.directory) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        else {
            NSDateFormatter *date = [[NSDateFormatter alloc] init]; date.dateStyle = NSDateFormatterShortStyle;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [NSByteCountFormatter stringFromByteCount:(int64_t)entry.size countStyle:NSByteCountFormatterCountStyleFile], [date stringFromDate:entry.modified]];
            cell.accessoryType = [_selected containsObject:entry.name] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (tableView == _rootTable) { _root = _roots[indexPath.row]; _path = @""; [self reloadDirectory]; }
    else if ((NSUInteger)indexPath.row >= _entries.count) { if (_nextOffset) [self loadPage:_nextOffset]; }
    else {
        FileTransferEntry *entry = _entries[indexPath.row];
        if (entry.directory) { _path = _path.length ? [_path stringByAppendingPathComponent:entry.name] : entry.name; [self reloadDirectory]; }
        else { if ([_selected containsObject:entry.name]) [_selected removeObject:entry.name]; else [_selected addObject:entry.name]; [self updateControls]; }
    }
}
@end
