#import "FileTransferViewController.h"
#import "RemoteFilesViewController.h"
#import "FileTransferClient.h"
#import "FileTransferManager.h"
#import "TemporaryHost.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuickLook/QuickLook.h>

static NSString *FTText(NSString *key) { return NSLocalizedStringFromTable(key, @"FileTransfer", nil); }
static NSString *FTErrorText(NSError *error) {
    if (![error.domain isEqualToString:FileTransferErrorDomain]) return error.localizedDescription;
    NSString *key = [@"error." stringByAppendingString:error.userInfo[@"reason"] ?: @"request_failed"];
    NSString *text = FTText(key); return [text isEqualToString:key] ? FTText(@"error.request_failed") : text;
}
static NSString *FTSize(uint64_t bytes) { return [NSByteCountFormatter stringFromByteCount:(int64_t)bytes countStyle:NSByteCountFormatterCountStyleFile]; }

@interface FileTransferActionControl : UIControl
- (instancetype)initWithIcon:(NSString *)icon text:(NSString *)text;
@end
@implementation FileTransferActionControl {
    UIView *_circle; UIImageView *_icon; UILabel *_label;
}
- (instancetype)initWithIcon:(NSString *)icon text:(NSString *)text {
    if ((self = [super init])) {
        _circle = [[UIView alloc] init]; _circle.backgroundColor = UIColor.systemBackgroundColor; _circle.layer.cornerRadius = 36; _circle.userInteractionEnabled = NO;
        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]]; _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = UIColor.systemBlueColor; [_circle addSubview:_icon]; [self addSubview:_circle];
        _label = [[UILabel alloc] init]; _label.text = text; _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _label.textColor = UIColor.labelColor; _label.textAlignment = NSTextAlignmentCenter; _label.numberOfLines = 3;
        _label.adjustsFontForContentSizeCategory = YES; [self addSubview:_label];
        self.isAccessibilityElement = YES; self.accessibilityLabel = text;
    } return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; _circle.frame = CGRectMake((self.bounds.size.width - 72) / 2, 12, 72, 72); _icon.frame = CGRectMake(16, 16, 40, 40);
    _label.frame = CGRectMake(4, 94, MAX(0, self.bounds.size.width - 8), MAX(0, self.bounds.size.height - 98));
}
- (CGSize)intrinsicContentSize { return CGSizeMake(100, 152); }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.alpha = enabled ? 1 : 0.4; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; _circle.alpha = highlighted ? 0.6 : 1; }
@end

@interface FileTransferTaskCell : UITableViewCell
- (void)configure:(FileTransferTask *)task manager:(FileTransferManager *)manager;
@end
@implementation FileTransferTaskCell {
    UILabel *_name, *_detail; UIImageView *_icon, *_direction; UIProgressView *_progress; UIStackView *_buttons;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        _name = [[UILabel alloc] init]; _name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _name.adjustsFontForContentSizeCategory = YES; _name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _detail = [[UILabel alloc] init]; _detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _detail.textColor = UIColor.secondaryLabelColor; _detail.numberOfLines = 0; _detail.adjustsFontForContentSizeCategory = YES;
        _progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _detail, _progress]]; text.axis = UILayoutConstraintAxisVertical; text.spacing = 7;
        _icon = [[UIImageView alloc] init]; _icon.contentMode = UIViewContentModeScaleAspectFit; _icon.tintColor = UIColor.systemBlueColor;
        _direction = [[UIImageView alloc] init]; _direction.contentMode = UIViewContentModeScaleAspectFit;
        _buttons = [[UIStackView alloc] init]; _buttons.axis = UILayoutConstraintAxisHorizontal; _buttons.spacing = 2;
        for (UIView *view in @[_icon, text, _buttons, _direction]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:view]; }
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18], [_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:32], [_icon.heightAnchor constraintEqualToConstant:36],
            [_direction.trailingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:4], [_direction.bottomAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:4],
            [_direction.widthAnchor constraintEqualToConstant:16], [_direction.heightAnchor constraintEqualToConstant:16],
            [text.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:16], [text.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:17],
            [text.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-17], [text.trailingAnchor constraintEqualToAnchor:_buttons.leadingAnchor constant:-8],
            [_buttons.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12], [_buttons.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]
        ]];
    } return self;
}
- (void)configure:(FileTransferTask *)task manager:(FileTransferManager *)manager {
    _name.text = task.name;
    BOOL finished = task.state == FileTransferCompleted || task.state == FileTransferCancelled;
    NSArray *states = @[@"state.preparing", @"state.queued", @"state.running", @"state.paused", @"state.failed", @"state.completed", @"state.cancelled"];
    NSString *state = FTText(states[task.state]);
    if (task.state == FileTransferRunning) state = FTText(task.upload ? @"state.sending" : @"state.receiving");
    NSDateFormatter *date = [[NSDateFormatter alloc] init]; date.dateStyle = NSDateFormatterShortStyle; date.timeStyle = NSDateFormatterNoStyle;
    _detail.text = task.state == FileTransferPreparing ? state : finished ? [NSString stringWithFormat:@"%@ · %@ · %@", [date stringFromDate:task.date], FTSize(task.size),
        task.state == FileTransferCancelled ? state : FTText(task.upload ? @"sent" : @"received")] :
        [NSString stringWithFormat:@"%@ · %@ / %@%@", state, FTSize(task.offset), FTSize(task.size), task.error ? [@"\n" stringByAppendingString:FTErrorText(task.error)] : @""];
    _icon.image = [UIImage systemImageNamed:@"doc.fill"]; _icon.tintColor = UIColor.secondaryLabelColor;
    _direction.image = [UIImage systemImageNamed:task.upload ? @"arrow.up.circle.fill" : @"arrow.down.circle.fill"];
    _direction.tintColor = task.state == FileTransferCompleted ? UIColor.systemGreenColor : UIColor.systemBlueColor;
    _progress.hidden = finished || task.state == FileTransferPreparing;
    _progress.progress = task.size ? (float)((double)task.offset / task.size) : 0;
    for (UIView *button in _buttons.arrangedSubviews.copy) [button removeFromSuperview];
    if (!finished) {
        if (task.state != FileTransferPreparing) {
            BOOL pause = task.state == FileTransferRunning || task.state == FileTransferQueued;
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setImage:[UIImage systemImageNamed:pause ? @"pause.circle" : @"play.circle"] forState:UIControlStateNormal];
            button.accessibilityLabel = FTText(pause ? @"pause" : task.state == FileTransferFailed ? @"retry" : @"resume");
            [button addAction:[UIAction actionWithHandler:^(UIAction *action) { if (pause) [manager pauseTask:task.identifier]; else [manager resumeTask:task.identifier]; }] forControlEvents:UIControlEventTouchUpInside];
            [_buttons addArrangedSubview:button]; [button.widthAnchor constraintEqualToConstant:36].active = YES; [button.heightAnchor constraintEqualToConstant:44].active = YES;
        }
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem]; [cancel setImage:[UIImage systemImageNamed:@"xmark.circle"] forState:UIControlStateNormal];
        cancel.accessibilityLabel = FTText(@"cancel"); [cancel addAction:[UIAction actionWithHandler:^(UIAction *action) { [manager cancelTask:task.identifier]; }] forControlEvents:UIControlEventTouchUpInside];
        [_buttons addArrangedSubview:cancel]; [cancel.widthAnchor constraintEqualToConstant:36].active = YES; [cancel.heightAnchor constraintEqualToConstant:44].active = YES;
    }
    self.selectionStyle = finished && task.state == FileTransferCompleted && !task.upload ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
}
@end

@interface FileTransferViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource>
@end
@implementation FileTransferViewController {
    TemporaryHost *_host; FileTransferManager *_manager; NSArray<FileTransferTask *> *_active, *_history;
    UIView *_header; UILabel *_status; FileTransferActionControl *_photos, *_files, *_browse;
    UISegmentedControl *_filter; NSURL *_previewURL; BOOL _reloadPending; NSInteger _pendingImports;
}
- (instancetype)initWithHost:(TemporaryHost *)host { return [self initWithHost:host manager:FileTransferManagerForHost(host)]; }
- (instancetype)initWithHost:(TemporaryHost *)host manager:(FileTransferManager *)manager {
    if ((self = [super initWithStyle:UITableViewStylePlain])) { _host = host; _manager = manager; _active = @[]; _history = @[]; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = _host.name; self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.accessibilityIdentifier = @"file-transfer-page"; self.edgesForExtendedLayout = UIRectEdgeNone;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = FTText(@"close");
    if (@available(iOS 26.0, *)) self.navigationItem.leftBarButtonItem.hidesSharedBackground = YES;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init]; [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColor.systemBackgroundColor; appearance.titleTextAttributes = @{NSForegroundColorAttributeName:UIColor.labelColor};
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;
    self.navigationController.navigationBar.tintColor = UIColor.labelColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 90;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 64, 0, 16);
    [self.tableView registerClass:FileTransferTaskCell.class forCellReuseIdentifier:@"transfer"];
    _header = [[UIView alloc] init]; _header.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _photos = [[FileTransferActionControl alloc] initWithIcon:@"photo.on.rectangle" text:FTText(@"send_photos")];
    _files = [[FileTransferActionControl alloc] initWithIcon:@"folder.fill" text:FTText(@"send_files")];
    _browse = [[FileTransferActionControl alloc] initWithIcon:@"desktopcomputer" text:FTText(@"browse")];
    _photos.accessibilityIdentifier = @"file-transfer-send-photos"; _files.accessibilityIdentifier = @"file-transfer-send-files"; _browse.accessibilityIdentifier = @"file-transfer-browse";
    [_photos addTarget:self action:@selector(selectPhotos) forControlEvents:UIControlEventTouchUpInside];
    [_files addTarget:self action:@selector(selectFiles) forControlEvents:UIControlEventTouchUpInside];
    [_browse addTarget:self action:@selector(browse) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[_photos, _files, _browse]]; actions.distribution = UIStackViewDistributionFillEqually;
    actions.translatesAutoresizingMaskIntoConstraints = NO; [_header addSubview:actions];
    _status = [[UILabel alloc] init]; _status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; _status.textColor = UIColor.secondaryLabelColor;
    _status.numberOfLines = 0; _status.textAlignment = NSTextAlignmentCenter; _status.translatesAutoresizingMaskIntoConstraints = NO; [_header addSubview:_status];
    [NSLayoutConstraint activateConstraints:@[[actions.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor constant:12], [actions.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor constant:-12],
        [actions.topAnchor constraintEqualToAnchor:_header.topAnchor constant:12], [actions.heightAnchor constraintGreaterThanOrEqualToConstant:152],
        [_status.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:6], [_status.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor constant:24],
        [_status.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor constant:-24], [_status.bottomAnchor constraintEqualToAnchor:_header.bottomAnchor constant:-16]]];
    self.tableView.tableHeaderView = _header;
    _filter = [[UISegmentedControl alloc] initWithItems:@[FTText(@"all"), FTText(@"received"), FTText(@"sent")]];
    _filter.selectedSegmentIndex = 0; [_filter addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = [[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed) name:FileTransferManagerDidChange object:_manager];
    [self reload]; [self refresh];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setNavigationBarHidden:NO animated:animated]; [self reload]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { __weak typeof(self) weakSelf = self; [_manager refreshCapabilities:^{ [weakSelf.refreshControl endRefreshing]; [weakSelf reload]; }]; }
- (void)changed {
    if (_reloadPending) return; _reloadPending = YES;
    __weak typeof(self) weakSelf = self; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        FileTransferViewController *controller = weakSelf; if (!controller) return; controller->_reloadPending = NO; [controller reload];
    });
}
- (void)reload {
    NSMutableArray *active = [NSMutableArray array], *history = [NSMutableArray array];
    for (FileTransferTask *task in _manager.tasks) {
        if (task.state != FileTransferCompleted && task.state != FileTransferCancelled) [active addObject:task];
        else if (_filter.selectedSegmentIndex == 0 || (task.state == FileTransferCompleted &&
            ((_filter.selectedSegmentIndex == 1 && !task.upload) || (_filter.selectedSegmentIndex == 2 && task.upload)))) [history addObject:task];
    }
    _active = active; _history = [history sortedArrayUsingComparator:^NSComparisonResult(FileTransferTask *a, FileTransferTask *b) { return [b.date compare:a.date]; }];
    BOOL ready = _manager.capabilities.enabled && !_manager.capabilityError;
    _photos.enabled = _files.enabled = ready && _manager.capabilities.upload; _browse.enabled = ready && _manager.capabilities.roots.count > 0;
    _status.text = _pendingImports > 0 ? FTText(@"state.preparing") : _manager.capabilityError ? FTErrorText(_manager.capabilityError) :
        !_manager.capabilitiesProbed ? FTText(@"checking") : !ready ? FTText(@"error.file_transfer_disabled") :
        !_manager.capabilities.upload ? FTText(@"error.upload_disabled") : _manager.capabilities.roots.count == 0 ? FTText(@"no_shares") : @"";
    [self.tableView reloadData]; [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [_header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(_header.frame.size.height - size.height) > 1 || _header.frame.size.width != width) {
        _header.frame = CGRectMake(0, 0, width, size.height); self.tableView.tableHeaderView = _header;
    }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? _active.count : MAX(1, _history.count); }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return section == 0 ? 56 : 106; }
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init]; header.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *title = [[UILabel alloc] init]; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; title.textColor = UIColor.secondaryLabelColor;
    title.text = [NSString stringWithFormat:FTText(section == 0 ? @"active_count" : @"history_count"), (unsigned long)(section == 0 ? _active.count : _history.count)];
    title.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:title];
    [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20].active = YES; [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:17].active = YES;
    if (section == 1) {
        UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem]; [clear setTitle:FTText(@"clear_history") forState:UIControlStateNormal];
        [clear setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal]; clear.translatesAutoresizingMaskIntoConstraints = NO;
        [clear addTarget:self action:@selector(clearHistory) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:clear];
        [clear.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16].active = YES; [clear.centerYAnchor constraintEqualToAnchor:title.centerYAnchor].active = YES;
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:clear.leadingAnchor constant:-8].active = YES;
        [_filter removeFromSuperview]; _filter.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:_filter];
        [NSLayoutConstraint activateConstraints:@[[_filter.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20], [_filter.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
            [_filter.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:15], [_filter.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-10]]];
    }
    return header;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && _history.count == 0) { UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.text = FTText(@"empty_history"); cell.textLabel.textColor = UIColor.tertiaryLabelColor; cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell; }
    FileTransferTask *task = indexPath.section == 0 ? _active[indexPath.row] : _history[indexPath.row];
    FileTransferTaskCell *cell = [tableView dequeueReusableCellWithIdentifier:@"transfer" forIndexPath:indexPath]; [cell configure:task manager:_manager]; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; if (indexPath.section != 1 || _history.count == 0) return;
    FileTransferTask *task = _history[indexPath.row]; if (task.state != FileTransferCompleted || task.upload) return;
    UIAlertController *actions = [UIAlertController alertControllerWithTitle:task.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actions addAction:[UIAlertAction actionWithTitle:FTText(@"preview") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self->_previewURL = task.localURL; QLPreviewController *preview = [[QLPreviewController alloc] init]; preview.dataSource = self; [self.navigationController pushViewController:preview animated:YES];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:FTText(@"save_files") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[task.localURL] asCopy:YES]; [self presentViewController:picker animated:YES completion:nil];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:FTText(@"share") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[task.localURL] applicationActivities:nil];
        share.popoverPresentationController.sourceView = self.tableView; share.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
        [self presentViewController:share animated:YES completion:nil];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:FTText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    actions.popoverPresentationController.sourceView = tableView; actions.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:actions animated:YES completion:nil];
}
- (void)clearHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:FTText(@"clear_history") message:FTText(@"clear_history_confirm") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:FTText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:FTText(@"clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self->_manager clearHistory]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)selectFiles {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection = YES; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { for (NSURL *url in urls) [_manager enqueueUpload:url name:nil]; }
- (void)selectPhotos {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init]; configuration.selectionLimit = 0;
    configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration]; picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil]; _pendingImports += results.count; [self reload];
    __weak typeof(self) weakSelf = self; FileTransferManager *manager = _manager;
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        NSString *type = [provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier] ? UTTypeMovie.identifier : UTTypeImage.identifier;
        [provider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *error) {
            NSString *name = provider.suggestedName;
            if (!FileTransferValidName(name)) name = url.lastPathComponent;
            if (name.pathExtension.length == 0 && url.pathExtension.length) name = [name stringByAppendingPathExtension:url.pathExtension];
            NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
            NSURL *copy = [folder URLByAppendingPathComponent:name ?: @"photo"];
            NSError *copyError = error;
            if (url && !copyError) { [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&copyError]; if (!copyError) [NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:&copyError]; }
            if (!url && !copyError) copyError = FileTransferError(@"local_file_unavailable", 0);
            if (!copyError) [manager enqueueUpload:copy name:name completion:^(NSError *failure) { [NSFileManager.defaultManager removeItemAtURL:folder error:nil]; }];
            dispatch_async(dispatch_get_main_queue(), ^{
                FileTransferViewController *controller = weakSelf; if (!controller) return;
                controller->_pendingImports--; [controller reload];
                if (copyError && !controller.presentedViewController) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:FTText(@"error_title") message:FTErrorText(copyError) preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:FTText(@"ok") style:UIAlertActionStyleDefault handler:nil]]; [controller presentViewController:alert animated:YES completion:nil];
                }
            });
        }];
    }
}
- (void)browse { [self.navigationController pushViewController:[[RemoteFilesViewController alloc] initWithManager:_manager] animated:YES]; }
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller { return _previewURL ? 1 : 0; }
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index { return _previewURL; }
@end
