//
//  ITPViewController.m
//  iTunesPicker
//
//  Created by Denis Berton on 17/02/14.
//  Copyright (c) 2014 appcorner.it. All rights reserved.
//

#import "ITPViewController.h"
#import "ITPPickerTableViewController.h"
#import "ITPCountryItemChartsViewController.h"
#import "ITPMenuTableViewController.h"
#import "ITPAppPickerDetailViewController.h"
#import "ITPSideMenuViewController.h"

#import "SwipeView.h"
#import "SVProgressHUD.h"

#define firstLoadDefaultEntityType kITunesEntityTypeSoftware; //default type on first open
#define maxOpenedPickers 20; //limit to max countries loaded on device, high value are network expensive and cause memory crash (not applied on simulator)

@interface ITPViewController () <SwipeViewDataSource, SwipeViewDelegate, ITPMenuTableViewDelegate>
{
    CGRect filterCloseFrame,filterOpenFrame;
    tITunesAppChartType rankingSelectedIndex;
    tITunesAppGenreType genreSelectedIndex;
    BOOL pickersLoading;
    BOOL firstLoad;
    NSUInteger maxRecordToLoadForCountry;
}

@property (nonatomic, weak) IBOutlet SwipeView *swipeView;
@property (nonatomic, strong) ITPMenuTableViewController *leftPanel;
@property (nonatomic, strong) ITPMenuTableViewController *rightPanel;

@end

@implementation ITPViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    maxRecordToLoadForCountry = kITunesMaxLimitLoadEntities; //max iTunes API records
    
    filterOpenFrame = self.filterView.frame;
    filterCloseFrame = filterOpenFrame;
    filterCloseFrame.origin.y -= self.filterView.frame.size.height;
    
    pickersLoading = NO;
    firstLoad = YES;
    _swipeView.pagingEnabled = YES;
    
    [self.countryButton setImage:[UIImage imageNamed:@"globe.png"] forState:UIControlStateNormal];
    self.pickerViews = [[NSMutableArray alloc]init];

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"save_picker_state"];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if(firstLoad)
    {
        firstLoad = NO;
        [self loadPickerState];
        if(!self.entitiesDatasources)
        {
            [self openUserCountryPicker:nil];
        }
    }
}

- (void)dealloc
{
    _swipeView.delegate = nil;
    _swipeView.dataSource = nil;
}

#pragma mark public

- (void)reloadWithEntityType:(tITunesEntityType)entityType
{
    if(self.entitiesDatasources.entityType != entityType)
    {
        
        //TODO: development message to remove on completion
        if(entityType != kITunesEntityTypeSoftware && entityType != kITunesEntityTypeMusic)
        {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Work in progress" message:@"Supported types: App, Music\nStay tuned!" delegate:self cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Cancel",nil), nil];
            [alert show];
            return;
        }

        NSString* userCountry = [self.entitiesDatasources.userCountry copy];
        NSArray* allPickerCountries = [[self.entitiesDatasources getAllCountries] copy];
        for (NSString* countryPicker in allPickerCountries) {
            [self removePickerTableViewForCountry:countryPicker];
        }
        
        self.entitiesDatasources = [[ACKEntitiesContainer alloc]initWithUserCountry:userCountry entityType:entityType limit:maxRecordToLoadForCountry];

        [self updateEntityMunuPanels];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
        
        if(allPickerCountries.count == 0)
        {
            allPickerCountries = @[userCountry];
        }
        for (NSString* country in allPickerCountries) {
            [self addPickerTableViewForCountry:country];
        }
        [self saveStatePickerApps];
        [_swipeView reloadData];
    }
}

#pragma mark Action

- (IBAction)countryAction:(id)sender {
    [self closeAllPanelsExcept:nil];
    ITPCountryItemChartsViewController *vc = [[ITPCountryItemChartsViewController alloc] initWithStyle:UITableViewStylePlain
                                                                                          allCountries:[ACKITunesQuery getITunesStoreCountries]
                                                                                     selectedCountries:[[NSSet alloc]initWithArray:[self.entitiesDatasources getAllCountries]]
                                                                                           userCountry:self.entitiesDatasources.userCountry
                                                                                           multiSelect:YES];
    vc.countriesSelectionLimit = maxOpenedPickers;
    vc.completionBlock = ^(NSArray *countries){
        NSArray* allPickerCountries = [[self.entitiesDatasources getAllCountries] copy];
        for (NSString* countryPicker in allPickerCountries) {
            if(![countries containsObject:countryPicker])
            {
                [self removePickerTableViewForCountry:countryPicker];
            }
        }
        for (NSString* country in countries) {
            if(![allPickerCountries containsObject:country])
            {
                [self addPickerTableViewForCountry:country];
            }
        }
        [self saveStatePickerApps];
        [_swipeView reloadData];
    };
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (IBAction)filterSxAction:(id)sender {
    [self toggleMenuPanel:sender];
}

- (IBAction)filterDxAction:(id)sender {
    [self toggleMenuPanel:sender];
}

- (IBAction)openUserCountryPicker:(id)sender {
    ITPCountryItemChartsViewController *vc = [[ITPCountryItemChartsViewController alloc] initWithStyle:UITableViewStylePlain
                                                                                          allCountries:[ACKITunesQuery getITunesStoreCountries]
                                                                                     selectedCountries:nil
                                                                                           userCountry:[NSLocale preferredLanguages][0]
                                                                                       multiSelect:NO];
    
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:vc];
    vc.navigationItem.title=NSLocalizedString(@"Select your iTunes Country",nil);
    vc.completionBlock = ^(NSArray *countries){
        [navigation dismissViewControllerAnimated:YES completion:NO];
        if(self.entitiesDatasources)
        {
            NSArray* allPickerCountries = [[self.entitiesDatasources getAllCountries] copy];
            for (NSString* countryPicker in allPickerCountries) {
                [self removePickerTableViewForCountry:countryPicker];
            }
        }
        tITunesEntityType entityType = self.entitiesDatasources?self.entitiesDatasources.entityType:firstLoadDefaultEntityType;
        self.entitiesDatasources = [[ACKEntitiesContainer alloc]initWithUserCountry:countries[0] entityType:entityType limit:maxRecordToLoadForCountry];
        [self setupMenuPanels];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
        
        [self addPickerTableViewForCountry:countries[0]];
        [self saveStatePickerApps];
        [_swipeView reloadData];
    };
    
    [self presentViewController:navigation animated:YES completion:nil];
}

- (IBAction)toggleFilter:(id)sender {
    [self toggleFilterPanelWithCompletionBlock:^(BOOL isOpen) {}];
}

#pragma mark ITPViewControllerDelegate

-(void)showPickerAtIndex:(NSInteger)index
{
    [_swipeView scrollToItemAtIndex:index duration:0.5];
}

-(void)selectEntity:(ACKITunesEntity*)entity
{
    NSArray* indexCharts = [self.entitiesDatasources getIndexesFromEntity:entity];
    
    BOOL indexFound = NO;
    for (NSNumber* index in indexCharts) {
        NSInteger position = [index integerValue];
        if(position != NSNotFound)
        {
            indexFound = YES;
            break;
        }
    }
    
    if(!indexFound)
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"App not in rankings",nil) message:NSLocalizedString(@"The selected App is not present in the rankings of countries loaded.",nil) delegate:self cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Cancel",nil), nil];
        [alert show];
        return;
    }
    
    ITPCountryItemChartsViewController *vc = [[ITPCountryItemChartsViewController alloc] initWithStyle:UITableViewStylePlain
                                                                                          allCountries:[self.entitiesDatasources getAllCountries]
                                                                                           indexCharts:indexCharts
                                                                                                  item:entity];
    vc.completionBlock = ^(NSArray *countries){};
    
    [self.navigationController pushViewController:vc animated:YES];
}

-(void)openITunesEntityDetail:(ACKITunesEntity*)entity
{
    if([entity isKindOfClass:[ACKApp class]]){
        ITPAppPickerDetailViewController* detailController = [[ITPAppPickerDetailViewController alloc]initWithNibName:nil bundle:nil];
        detailController.appObject = (ACKApp*)entity;
        ITPPickerTableViewController* picker = entity.userData;
        detailController.pickerCountry = picker.country;
        detailController.allowsSelection = !picker.loadWithArtistId;
        entity.userData = nil;
        detailController.delegate = self;
        [self.navigationController pushViewController:detailController animated:YES];
    }
}

#pragma mark SwipeViewDataSource

- (NSInteger)numberOfItemsInSwipeView:(SwipeView *)swipeView
{
    return  self.entitiesDatasources.datasourcesCount;
}

- (UIView *)swipeView:(SwipeView *)swipeView viewForItemAtIndex:(NSInteger)index reusingView:(UIView *)view
{
    ITPPickerTableViewController* picker = (ITPPickerTableViewController*)self.pickerViews[index];
    return picker.view;
}

#pragma mark SwipeViewDelegate

- (CGSize)swipeViewItemSize:(SwipeView *)swipeView
{
    return self.swipeView.bounds.size;
}

- (void)swipeView:(SwipeView *)swipeView didSelectItemAtIndex:(NSInteger)index
{
    ITPPickerTableViewController* picker = ((ITPPickerTableViewController*)self.pickerViews[index]);
    [picker.searchBar resignFirstResponder];
}

-(void)showLoadingHUD:(BOOL)loading
{
    if(pickersLoading == loading)
    {
        return;
    }
    
    BOOL tmpPickersLoading = NO;
    for (ITPPickerTableViewController* pickerTableView in self.pickerViews) {
        tmpPickersLoading = tmpPickersLoading || pickerTableView.loading;
    }
    
    if(tmpPickersLoading == pickersLoading)
    {
        return;
    }
    
    pickersLoading = tmpPickersLoading;
    if(pickersLoading)
    {
        [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeGradient];
    }
    else
    {
        [SVProgressHUD dismiss];
    }
}

#pragma mark private

-(ITPPickerTableViewController*) addPickerTableViewForCountry:(NSString*)country
{
    ITPPickerTableViewController* pickerTableView = [[ITPPickerTableViewController alloc]initWithNibName:nil bundle:nil];
    pickerTableView.delegate = self;
    [self.pickerViews addObject:pickerTableView];
    
    [pickerTableView loadChartInITunesStoreCountry:country withType:rankingSelectedIndex withGenre:genreSelectedIndex completionBlock:^(NSArray *array, NSError *err) {
        [_swipeView reloadData];
    }];
    
    return pickerTableView;
}

-(void) refreshAllPickers
{
    NSInteger i = 0;
    for (ITPPickerTableViewController* pickerTableView in self.pickerViews) {
        [pickerTableView loadChartInITunesStoreCountry:[self.entitiesDatasources getAllCountries][i] withType:rankingSelectedIndex withGenre:genreSelectedIndex completionBlock:^(NSArray *array, NSError *err) {
            [_swipeView reloadData];
        }];
        i++;
    }
}

-(void) removePickerTableViewForCountry:(NSString*)country
{
    NSInteger index = [[self.entitiesDatasources getAllCountries]indexOfObject:country];
    if(index ==  NSNotFound)
    {
        return;
    }
    [self.entitiesDatasources removeDatasourceAtIndex:index];
    [self.pickerViews removeObjectAtIndex:index];
    [_swipeView reloadData];
}

-(void)toggleFilterPanelWithCompletionBlock:(void (^)(BOOL isOpen))completion
{
    if(self.filterView.hidden)
    {
        self.filterView.frame = filterCloseFrame;
    }
    BOOL hide = !self.filterView.hidden;
    [UIView animateWithDuration:0.4 animations:^{
        if(!self.filterView.hidden){
            self.filterView.frame = filterCloseFrame;
            [self closeAllPanelsExcept:nil];
        }
        else
        {
            ITPPickerTableViewController* picker = (ITPPickerTableViewController*)self.pickerViews[self.swipeView.currentItemIndex];
            [picker.searchBar resignFirstResponder];
            self.filterView.hidden = NO;
            self.filterView.frame = filterOpenFrame;
        }
    } completion:^(BOOL finished) {
        self.filterView.hidden = hide;
        if(completion)
        {
            completion(!self.filterView.hidden);
        }
    }];
}

-(void)setupMenuPanels
{
    CGRect frame = self.swipeView.frame;
    frame.origin.y += self.filterView.frame.size.height;
    frame.size.height -= self.filterView.frame.size.height;
    
    if(!self.leftPanel)
    {
        self.leftPanel = [[ITPMenuTableViewController alloc]initWithNibName:nil bundle:nil];
    }
    self.leftPanel.type = kPAPMenuPickerTypeRanking;
    self.leftPanel.openDirection = kPAPMenuOpenDirectionRight;
    self.leftPanel.delegate = self;
    
    if(!self.rightPanel)
    {
        self.rightPanel = [[ITPMenuTableViewController alloc]initWithNibName:nil bundle:nil];
    }
    self.rightPanel.type = kPAPMenuPickerTypeGenre;
    self.rightPanel.openDirection = kPAPMenuOpenDirectionLeft;
    self.rightPanel.delegate = self;
    
    [self updateEntityMunuPanels];
    
    [self.view insertSubview:self.leftPanel.view belowSubview:self.filterView];
    self.leftPanel.openFrame = frame;
    self.leftPanel.backgroundAreaDismissRect = self.swipeView.frame;
    
    [self.view insertSubview:self.rightPanel.view belowSubview:self.filterView];
    self.rightPanel.openFrame = frame;
    self.rightPanel.backgroundAreaDismissRect = self.swipeView.frame;
    
}

-(void) updateEntityMunuPanels
{
    if(self.entitiesDatasources.entityType == kITunesEntityTypeSoftware)
    {
        self.leftPanel.items = [ACKITunesQuery getAppChartType];
        self.rightPanel.items = [ACKITunesQuery getAppGenreType];
    }
    else if(self.entitiesDatasources.entityType == kITunesEntityTypeMusic)
    {
        self.leftPanel.items = [ACKITunesQuery getMusicChartType];
        self.rightPanel.items = [ACKITunesQuery getMusicGenreType];
    }
    else
    {
        //TODO: remove default app on completion
        self.leftPanel.items = [ACKITunesQuery getAppChartType];
        self.rightPanel.items = [ACKITunesQuery getAppGenreType];
    }
}

-(void)valueSelectedAtIndex:(NSInteger)index forType:(tPAPMenuPickerType)type refreshPickers:(BOOL)refresh
{
    switch (type) {
        case kPAPMenuPickerTypeRanking:
            rankingSelectedIndex = index;
            [self.filterSxButton setTitle: NSLocalizedString(self.leftPanel.items[rankingSelectedIndex],@"") forState: UIControlStateNormal];
            if(self.leftPanel.isOpen)
                [self toggleMenuPanel:self.filterSxButton];
            [self.leftPanel.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
            break;
        case kPAPMenuPickerTypeGenre:
            genreSelectedIndex = index;
            [self.filterDxButton setTitle:NSLocalizedString(self.rightPanel.items[genreSelectedIndex],@"") forState: UIControlStateNormal];
            if(self.rightPanel.isOpen)
                [self toggleMenuPanel:self.filterDxButton];
            [self.rightPanel.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
            break;
    }
    if(refresh)
    {
        [self saveStatePickerApps];
        [self refreshAllPickers];
    }
}

- (void)toggleMenuPanel:(id)sender
{
    if(sender == self.filterSxButton)
    {
        [self closeAllPanelsExcept:self.leftPanel];
        [self.leftPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
        }];
    }
    else if(sender == self.filterDxButton)
    {
        [self closeAllPanelsExcept:self.rightPanel];
        [self.rightPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
        }];
    }
}

-(void) closeAllPanelsExcept:(ITPMenuTableViewController*)panel
{
    if(panel != self.leftPanel && self.leftPanel.isOpen)
        [self.leftPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
        }];
    if(panel != self.rightPanel && self.rightPanel.isOpen)
        [self.rightPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
        }];
}

-(void)loadPickerState
{
    NSDictionary *defaultUserDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithInteger:-1], @"saved_picker_ranking",
                                         [NSNumber numberWithInteger:-1], @"saved_picker_genre",
                                         [[NSArray alloc]init], @"saved_picker_countries",
                                         @"", @"saved_picker_usercountry",
                                         nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultUserDefaults];
    
    BOOL loadDefault = YES;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"save_picker_state"])
    {
        NSInteger ranking = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_ranking"];
        NSInteger genre = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_genre"];
        NSInteger entityType = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_entitytype"];
        NSArray* countries = [[NSUserDefaults standardUserDefaults] arrayForKey:@"saved_picker_countries"];
        NSString* userCountry = [[NSUserDefaults standardUserDefaults] stringForKey:@"saved_picker_usercountry"];
        
        if(ranking != -1 && genre != -1 && countries.count > 0)
        {
            self.entitiesDatasources = [[ACKEntitiesContainer alloc]initWithUserCountry:userCountry entityType:entityType limit:maxRecordToLoadForCountry];
            [self setupMenuPanels];
            [self valueSelectedAtIndex:ranking forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
            [self valueSelectedAtIndex:genre forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
            for (NSString* country in countries) {
                [self addPickerTableViewForCountry:country];
            }
            loadDefault = NO;
        }
    }
    if(loadDefault)
    {
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
    }
    else
    {
        [_swipeView reloadData];
    }
}

-(void)saveStatePickerApps
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"save_picker_state"])
    {
        [[NSUserDefaults standardUserDefaults] setInteger:rankingSelectedIndex forKey:@"saved_picker_ranking"];
        [[NSUserDefaults standardUserDefaults] setInteger:genreSelectedIndex forKey:@"saved_picker_genre"];
        [[NSUserDefaults standardUserDefaults] setInteger:self.entitiesDatasources.entityType forKey:@"saved_picker_entitytype"];
        [[NSUserDefaults standardUserDefaults] setValue:[self.entitiesDatasources getAllCountries] forKey:@"saved_picker_countries"];
        [[NSUserDefaults standardUserDefaults] setValue:self.entitiesDatasources.userCountry forKey:@"saved_picker_usercountry"];
    }
}


@end
