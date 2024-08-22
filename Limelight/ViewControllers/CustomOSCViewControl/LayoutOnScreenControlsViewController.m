//
//  LayoutOnScreenControlsViewController.m
//  Moonlight
//
//  Created by Long Le on 9/27/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import "LayoutOnScreenControlsViewController.h"
#import "OSCProfilesTableViewController.h"
#import "OnScreenButtonState.h"
//#import "OnScreenControls.h"
#import "OSCProfilesManager.h"
#import "LocalizationHelper.h"
#import "Moonlight-Swift.h"

@interface LayoutOnScreenControlsViewController ()

@end


@implementation LayoutOnScreenControlsViewController {
    BOOL isToolbarHidden;
    OSCProfilesManager *profilesManager;
    __weak IBOutlet NSLayoutConstraint *toolbarTopConstraintiPhone;
    __weak IBOutlet NSLayoutConstraint *toolbarTopConstraintiPad;
}

@synthesize trashCanButton;
@synthesize undoButton;
@synthesize OSCSegmentSelected;
@synthesize toolbarRootView;
@synthesize chevronView;
@synthesize chevronImageView;


- (void) viewWillDisappear:(BOOL)animated{
    OnScreenKeyboardButtonView.editMode = false;
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OscLayoutCloseNotification" object:self];
}

- (void) reloadOnScreenKeyboardButtons {
    /*
    [self.onScreenKeyViewsDict enumerateKeysAndObjectsUsingBlock:^(id timeIntervalKey, id keyView, BOOL *stop) {
        [keyView removeFromSuperview];
    }];*/
    
    for (UIView *subview in self.view.subviews) {
        // 检查子视图是否是特定类型的实例
        if ([subview isKindOfClass:[OnScreenKeyboardButtonView class]]) {
            // 如果是，就添加到将要被移除的数组中
            [subview removeFromSuperview];
        }
    }
    
    [self.onScreenKeyViewsDict removeAllObjects];
    
    NSLog(@"reload os Key here");
    
    // _activeCustomOscButtonPositionDict will be updated every time when the osc profile is reloaded
    OSCProfile *oscProfile = [profilesManager getSelectedProfile]; //returns the currently selected OSCProfile
    for (NSData *buttonStateEncoded in oscProfile.buttonStates) {
        OnScreenButtonState* buttonState = [NSKeyedUnarchiver unarchivedObjectOfClass:[OnScreenButtonState class] fromData:buttonStateEncoded error:nil];
        if(buttonState.buttonType == KeyboardButton){
            OnScreenKeyboardButtonView* keyView = [[OnScreenKeyboardButtonView alloc] initWithKeyString:buttonState.name keyLabel:buttonState.alias]; //reconstruct keyView
            keyView.translatesAutoresizingMaskIntoConstraints = NO; // weird but this is mandatory, or you will find no key views added to the right place
            keyView.timestamp = buttonState.timestamp; // will be set as key in in the dict.
            // Add the KeyView to the view controller's view
            [self.view addSubview:keyView];
            [keyView setKeyLocationWithXOffset:buttonState.position.x yOffset:buttonState.position.y];
            
            [self.onScreenKeyViewsDict setObject:keyView forKey:@(keyView.timestamp)];
        }
    }
        
    //////////////////
    /*
    [self.onScreenKeyViewsDict enumerateKeysAndObjectsUsingBlock:^(id timeIntervalKey, id keyView, BOOL *stop) {
        [self.view addSubview:keyView];
    }];*/
    
}


- (void) viewDidLoad {
    [super viewDidLoad];
    profilesManager = [OSCProfilesManager sharedManager];
    self.onScreenKeyViewsDict = [[NSMutableDictionary alloc] init]; // will be revised to read persisted data , somewhere else
    [OSCProfilesManager setOnScreenKeyViewsDict:self.onScreenKeyViewsDict];   // pass the keyboard button dict to profiles manager

    isToolbarHidden = NO;   // keeps track if the toolbar is hidden up above the screen so that we know whether to hide or show it when the user taps the toolbar's hide/show button
            
    /* add curve to bottom of chevron tab view */
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:self.chevronView.bounds byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight) cornerRadii:CGSizeMake(10.0, 10.0)];
    CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
    maskLayer.frame = self.view.bounds;
    maskLayer.path  = maskPath.CGPath;
    self.chevronView.layer.mask = maskLayer;
    
    /* Add swipe gesture to toolbar to allow user to swipe it up and off screen */
    UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(moveToolbar:)];
    swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
    [self.toolbarRootView addGestureRecognizer:swipeUp];

    /* Add tap gesture to toolbar's chevron to allow user to tap it in order to move the toolbar on and off screen */
    UITapGestureRecognizer *singleFingerTap =
      [[UITapGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(moveToolbar:)];
    [self.chevronView addGestureRecognizer:singleFingerTap];

    self.layoutOSC = [[LayoutOnScreenControls alloc] initWithView:self.view controllerSup:nil streamConfig:nil oscLevel:OSCSegmentSelected];
    self.layoutOSC._level = OnScreenControlsLevelCustom;
    [self.layoutOSC show];  // draw on screen controls
    
    [self addInnerAnalogSticksToOuterAnalogLayers]; // allows inner and analog sticks to be dragged together around the screen together as one unit which is the expected behavior

    self.undoButton.alpha = 0.3;    // no changes to undo yet, so fade out the undo button a bit
    
    if ([[profilesManager getAllProfiles] count] == 0) { // if no saved OSC profiles exist yet then create one called 'Default' and associate it with Moonlight's legacy 'Full' OSC layout that's already been laid out on the screen at this point
        [profilesManager saveProfileWithName:@"Default" andButtonLayers:self.layoutOSC.OSCButtonLayers];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileRefresh)
                                                 name:@"OscLayoutTableViewCloseNotification"
                                               object:nil];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadOnScreenKeyboardButtons)
                                                 name:@"OscLayoutProfileSelctedInTableView"   // This is a special notification for reloading the on screen keyboard buttons. which can't be executed by _oscProfilesTableViewController.needToUpdateOscLayoutTVC code block, and has to be triggered by a notification
                                               object:nil];

    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(OSCLayoutChanged) name:@"OSCLayoutChanged" object:nil];    // used to notifiy this view controller that the user made a change to the OSC layout so that the VC can either fade in or out its 'Undo button' which will signify to the user whether there are any OSC layout changes to undo
    
    /* This will animate the toolbar with a subtle up and down motion intended to telegraph to the user that they can hide the toolbar if they wish*/
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        [UIView animateWithDuration:0.3
          delay:0.25
          usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
          options:UIViewAnimationOptionCurveEaseInOut animations:^{ // Animate toolbar up a a very small distance. Note the 0.35 time delay is necessary to avoid a bug that keeps animations from playing if the animation is presented immediately on a modally presented VC
            self.toolbarRootView.frame = CGRectMake(self.toolbarRootView.frame.origin.x, self.toolbarRootView.frame.origin.y - 25, self.toolbarRootView.frame.size.width, self.toolbarRootView.frame.size.height);
            }
          completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3
              delay:0
              usingSpringWithDamping:0.7
              initialSpringVelocity:1.0
              options:UIViewAnimationOptionCurveEaseIn animations:^{ // Animate the toolbar back down that same distance
                self.toolbarRootView.frame = CGRectMake(self.toolbarRootView.frame.origin.x, self.toolbarRootView.frame.origin.y + 25, self.toolbarRootView.frame.size.width, self.toolbarRootView.frame.size.height);
                }
              completion:^(BOOL finished) {
                NSLog (@"done");
            }];
        }];
    });
    [self profileRefresh];
}



- (void) viewDidAppear:(BOOL)animated {
    OnScreenKeyboardButtonView.editMode = true;
    [super viewWillAppear:animated];
    [self profileRefresh];
}


#pragma mark - Class Helper Functions

/* fades the 'Undo Button' in or out depending on whether the user has any OSC layout changes to undo */
- (void) OSCLayoutChanged {
    if ([self.layoutOSC.layoutChanges count] > 0) {
        self.undoButton.alpha = 1.0;
    }
    else {
        self.undoButton.alpha = 0.3;
    }
}

/* animates the toolbar up and off the screen or back down onto the screen */
- (void) moveToolbar:(UISwipeGestureRecognizer *)sender {
    BOOL isPad = [[UIDevice currentDevice].model hasPrefix:@"iPad"];
    NSLayoutConstraint *toolbarTopConstraint = isPad ? self->toolbarTopConstraintiPad : self->toolbarTopConstraintiPhone;
    if (isToolbarHidden == NO) {
        [UIView animateWithDuration:0.2 animations:^{   // animates toolbar up and off screen
            toolbarTopConstraint.constant -= self.toolbarRootView.frame.size.height;
            [self.view layoutIfNeeded];

        }
        completion:^(BOOL finished) {
            if (finished) {
                self->isToolbarHidden = YES;
                self.chevronImageView.image = [UIImage imageNamed:@"ChevronCompactDown"];
            }
        }];
    }
    else {
        [UIView animateWithDuration:0.2 animations:^{   // animates the toolbar back down into the screen
            toolbarTopConstraint.constant += self.toolbarRootView.frame.size.height;
            [self.view layoutIfNeeded];
        }
        completion:^(BOOL finished) {
            if (finished) {
                self->isToolbarHidden = NO;
                self.chevronImageView.image = [UIImage imageNamed:@"ChevronCompactUp"];
            }
        }];
    }
}

/**
 * Makes the inner analog stick layers a child layer of its corresponding outer analog stick layers so that both the inner and its corresponding outer layers move together when the user drags them around the screen as is the expected behavior when laying out OSC. Note that this is NOT expected behavior on the game stream view where the inner analog sticks move to follow toward the user's touch and their corresponding outer analog stick layers do not move
 */
- (void)addInnerAnalogSticksToOuterAnalogLayers {
    // right stick
    [self.layoutOSC._rightStickBackground addSublayer: self.layoutOSC._rightStick];
    self.layoutOSC._rightStick.position = CGPointMake(self.layoutOSC._rightStickBackground.frame.size.width / 2, self.layoutOSC._rightStickBackground.frame.size.height / 2);
    
    // left stick
    [self.layoutOSC._leftStickBackground addSublayer: self.layoutOSC._leftStick];
    self.layoutOSC._leftStick.position = CGPointMake(self.layoutOSC._leftStickBackground.frame.size.width / 2, self.layoutOSC._leftStickBackground.frame.size.height / 2);
}


#pragma mark - UIButton Actions

- (IBAction) closeTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction) trashCanTapped:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Delete Buttons Here"] message:[LocalizationHelper localizedStringForKey:@"Drag and drop buttons onto this trash can to remove them from the interface"] preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *ok = [UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction) undoTapped:(id)sender {
    if ([self.layoutOSC.layoutChanges count] > 0) { // check if there are layout changes to roll back to
        OnScreenButtonState *buttonState = [self.layoutOSC.layoutChanges lastObject];   //  Get the 'OnScreenButtonState' object that contains the name, position, and visiblity state of the button the user last moved
        
        CALayer *buttonLayer = [self.layoutOSC buttonLayerFromName:buttonState.name];   // get the on screen button layer that corresponds with the 'OnScreenButtonState' object that we retrieved above
        
        /* Set the button's position and visiblity to what it was before the user last moved it */
        buttonLayer.position = buttonState.position;
        buttonLayer.hidden = buttonState.isHidden;
        
        /* if user is showing or hiding dPad, then show or hide all four dPad button child layers as well since setting the 'hidden' property on the parent CALayer is not automatically setting the individual dPad child CALayers */
        if ([buttonLayer.name isEqualToString:@"dPad"]) {
            self.layoutOSC._upButton.hidden = buttonState.isHidden;
            self.layoutOSC._rightButton.hidden = buttonState.isHidden;
            self.layoutOSC._downButton.hidden = buttonState.isHidden;
            self.layoutOSC._leftButton.hidden = buttonState.isHidden;
        }
        
        /* if user is showing or hiding the left or right analog sticks, then show or hide their corresponding inner analog stick child layers as well since setting the 'hidden' property on the parent analog stick doesn't automatically hide its child inner analog stick CALayer */
        if ([buttonLayer.name isEqualToString:@"leftStickBackground"]) {
            self.layoutOSC._leftStick.hidden = buttonState.isHidden;
        }
        if ([buttonLayer.name isEqualToString:@"rightStickBackground"]) {
            self.layoutOSC._rightStick.hidden = buttonState.isHidden;
        }
        
        [self.layoutOSC.layoutChanges removeLastObject];
        
        [self OSCLayoutChanged]; // will fade the undo button in or out depending on whether there are any further changes to undo
    }
    else {  // there are no changes to undo. let user know there are no changes to undo
        UIAlertController * savedAlertController = [UIAlertController alertControllerWithTitle: [LocalizationHelper localizedStringForKey:@"Nothing to Undo"] message: [LocalizationHelper localizedStringForKey: @"There are no changes to undo"] preferredStyle:UIAlertControllerStyleAlert];
        [savedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [savedAlertController dismissViewControllerAnimated:NO completion:nil];
        }]];
        [self presentViewController:savedAlertController animated:YES completion:nil];
    }
}

- (IBAction) addTapped:(id)sender{
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"New Keyboard Button"]
                                                                             message:[LocalizationHelper localizedStringForKey:@"Enter the command & key label"]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = [LocalizationHelper localizedStringForKey:@"Command"];
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.spellCheckingType = UITextSpellCheckingTypeNo;
    }];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = [LocalizationHelper localizedStringForKey:@"Key label (optional)"];
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.spellCheckingType = UITextSpellCheckingTypeNo;
    }];

    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Cancel"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"OK"]
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction *action) {
        /*
        alertController.textFields[0].keyboardType = UIKeyboardTypeASCIICapable;
        alertController.textFields[0].autocorrectionType = UITextAutocorrectionTypeNo;
        alertController.textFields[0].spellCheckingType = UITextSpellCheckingTypeNo;
        alertController.textFields[1].keyboardType = UIKeyboardTypeASCIICapable;
        alertController.textFields[1].autocorrectionType = UITextAutocorrectionTypeNo;
        alertController.textFields[1].spellCheckingType = UITextSpellCheckingTypeNo;*/
        
        NSString *keyboardCmdString = [alertController.textFields[0].text uppercaseString]; // convert to uppercase
        NSString *keyLabel = alertController.textFields[1].text;
        if([keyLabel isEqualToString:@""]) keyLabel = [[keyboardCmdString lowercaseString] capitalizedString];
        if([CommandManager.shared extractKeyStringsFrom:keyboardCmdString] == nil) return; // this is a invalid string.
        
        //saving & present the keyboard button:
        OnScreenKeyboardButtonView* keyView = [[OnScreenKeyboardButtonView alloc] initWithKeyString:keyboardCmdString keyLabel:keyLabel];
        keyView.translatesAutoresizingMaskIntoConstraints = NO; // weird but this is mandatory, or you will find no key views added to the right place
        keyView.timestamp = CACurrentMediaTime(); // will be set as key in in the dict.
        [self.onScreenKeyViewsDict setObject:keyView forKey:@(keyView.timestamp)];
        // Add the KeyView to the view controller's view
        [self.view addSubview:keyView];
        [keyView setKeyLocationWithXOffset:50 yOffset:50];
    }];
    [alertController addAction:cancelAction];
    [alertController addAction:okAction];
    [self presentViewController:alertController animated:YES completion:nil];
}



/* show pop up notification that lets users choose to save the current OSC layout configuration as a profile they can load when they want. User can also choose to cancel out of this pop up */
- (IBAction) saveTapped:(id)sender {
    
    if([self->profilesManager updateSelectedProfile:self.layoutOSC.OSCButtonLayers]){
        UIAlertController * savedAlertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Current profile updated successfully"] preferredStyle:UIAlertControllerStyleAlert];
        [savedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        }]];
        [self presentViewController:savedAlertController animated:YES completion:nil];
    }
    else{
        UIAlertController * savedAlertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Profile Default can not be overwritten"] preferredStyle:UIAlertControllerStyleAlert];
        [savedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self.oscProfilesTableViewController profileViewRefresh]; // execute this will reset layout in OSC tool!
        }]];
        [self presentViewController:savedAlertController animated:YES completion:nil];
    }
}



/* Basically the same method as loadTapped, without parameter*/
// Make sure whenever self view controller load the selected profile and layout its buttons.
- (void)profileRefresh{
    UIStoryboard *storyboard;
    BOOL isIPhone = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone);
    if (isIPhone) {
        storyboard = [UIStoryboard storyboardWithName:@"iPhone" bundle:nil];
    }
    else {
        storyboard = [UIStoryboard storyboardWithName:@"iPad" bundle:nil];
    }
    
    // Center the current profile lable horizontally:;
    // Calculate the x-position
    CGFloat xPosition = (self.view.bounds.size.width - self.currentProfileLabel.frame.size.width) / 2;
    // Set the label's frame with the calculated x-position
    self.currentProfileLabel.frame = CGRectMake(xPosition, self.currentProfileLabel.frame.origin.y, self.currentProfileLabel.frame.size.width, self.currentProfileLabel.frame.size.height);
    self.currentProfileLabel.hidden = NO; // Show Current Profile display
    [self.currentProfileLabel setText:[LocalizationHelper localizedStringForKey:@"Current Profile: %@",[profilesManager getSelectedProfile].name]]; // display current profile name when profile is being refreshed.
    
    //initialiaze _oscProfilesTableViewController
    self->_oscProfilesTableViewController = [storyboard instantiateViewControllerWithIdentifier:@"OSCProfilesTableViewController"];
    
    //this part is just for registration, will not be immediately executed.
    self->_oscProfilesTableViewController.needToUpdateOscLayoutTVC = ^() {   // a block that will be called when the modally presented 'OSCProfilesTableViewController' VC is dismissed. By the time the 'OSCProfilesTableViewController' VC is dismissed the user would have potentially selected a different OSC profile with a different layout and they want to see this layout on this 'LayoutOnScreenControlsViewController.' This block of code will load the profile and then hide/show and move each OSC button to their appropriate position
        [self.layoutOSC updateControls];  // creates and saves a 'Default' OSC profile or loads the one the user selected on the previous screen
        [self addInnerAnalogSticksToOuterAnalogLayers];
        [self.layoutOSC.layoutChanges removeAllObjects];  // since a new OSC profile is being loaded, this will remove all previous layout changes made from the array
        [self OSCLayoutChanged];    // fades the 'Undo Button' out
        self->_oscProfilesTableViewController.currentOSCButtonLayers = self.layoutOSC.OSCButtonLayers; //pass updated OSCLayout to OSCProfileTableView again
        //[self reloadOnScreenKeyboardButtons];
    };
    
    [self.oscProfilesTableViewController profileViewRefresh]; // execute this will make sure OSCLayout is updated from persisted profile, not any cache.
    [self reloadOnScreenKeyboardButtons];

    // [self presentViewController:vc animated:YES completion:nil];
}


/* Presents the view controller that lists all OSC profiles the user can choose from */
- (IBAction) loadTapped:(id)sender {
    UIStoryboard *storyboard;
    BOOL isIPhone = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone);
    if (isIPhone) {
        storyboard = [UIStoryboard storyboardWithName:@"iPhone" bundle:nil];
    }
    else {
        storyboard = [UIStoryboard storyboardWithName:@"iPad" bundle:nil];
    }
    
    _oscProfilesTableViewController = [storyboard instantiateViewControllerWithIdentifier:@"OSCProfilesTableViewController"] ;
    
    _oscProfilesTableViewController.needToUpdateOscLayoutTVC = ^() {   // a block that will be called when the modally presented 'OSCProfilesTableViewController' VC is dismissed. By the time the 'OSCProfilesTableViewController' VC is dismissed the user would have potentially selected a different OSC ofile with a different layout and they want to see this layout on this 'LayoutOnScreenControlsViewController.' This block of code will load the profile and then hide/show and move each OSC button to their appropriate position
        [self.layoutOSC updateControls];  // creates and saves a 'Default' OSC profile or loads the one the user selected on the previous screen
        
        [self addInnerAnalogSticksToOuterAnalogLayers];
        
        [self.layoutOSC.layoutChanges removeAllObjects];  // since a new OSC profile is being loaded, this will remove all previous layout changes made from the array
        
        [self OSCLayoutChanged];    // fades the 'Undo Button' out
    };
    self.currentProfileLabel.hidden = YES; // Hide Current Profile display before entering the profile table view
    _oscProfilesTableViewController.currentOSCButtonLayers = self.layoutOSC.OSCButtonLayers;
    [self presentViewController:_oscProfilesTableViewController animated:YES completion:nil];
}


#pragma mark - Touch

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch* touch in touches) {
        
        CGPoint touchLocation = [touch locationInView:self.view];
        touchLocation = [[touch view] convertPoint:touchLocation toView:nil];
        CALayer *layer = [self.view.layer hitTest:touchLocation];
        
        if (layer == self.toolbarRootView.layer ||
            layer == self.chevronView.layer ||
            layer == self.chevronImageView.layer ||
            layer == self.toolbarStackView.layer ||
            layer == self.view.layer) {  // don't let user move toolbar or toolbar UI buttons, toolbar's chevron 'pull tab', or the layer associated with this VC's view
            return;
        }
    }
    [self.layoutOSC touchesBegan:touches withEvent:event];
}

- (void) touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {

    // -------- for OSC buttons
    [self.layoutOSC touchesMoved:touches withEvent:event];
    if ([self.layoutOSC isLayer:self.layoutOSC.layerBeingDragged
                        hoveringOverButton:trashCanButton]) { // check if user is dragging around a button and hovering it over the trash can button
        trashCanButton.tintColor = [UIColor redColor];
    }
    else {
        trashCanButton.tintColor = [UIColor colorWithRed:171.0/255.0 green:157.0/255.0 blue:255.0/255.0 alpha:1];
    }
    
    // -------- for keyboard Buttons
    UITouch *touch = [touches anyObject]; // Get the first touch in the set
    if([self touchWithinTashcanButton:touch]){
        trashCanButton.tintColor = [UIColor redColor];
    }
    else trashCanButton.tintColor = [UIColor colorWithRed:171.0/255.0 green:157.0/255.0 blue:255.0/255.0 alpha:1];

    
}

- (bool)touchWithinTashcanButton:(UITouch* )touch {
    CGPoint locationInView = [touch locationInView:self.view];
    
    // Convert the location to the button's coordinate system
    CGPoint locationInButton = [self.view convertPoint:locationInView toView:trashCanButton];
    bool ret = CGRectContainsPoint(trashCanButton.bounds, locationInButton);
    NSLog(@"within button: %d", ret);
    // Check if the location is within the button's bounds
    return ret;
}


- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    
    // removing keyboard buttons objs
    UITouch *touch = [touches anyObject]; // Get the first touch in the set
    if([self touchWithinTashcanButton:touch]){
        [self.onScreenKeyViewsDict[@(OnScreenKeyboardButtonView.timestampOfButtonBeingDragged)] removeFromSuperview];
        [self.onScreenKeyViewsDict removeObjectForKey:@(OnScreenKeyboardButtonView.timestampOfButtonBeingDragged)];
        OnScreenKeyboardButtonView.timestampOfButtonBeingDragged = 0; //reset thie timestamp
    }
    
    
    //removing OSC buttons
    if (self.layoutOSC.layerBeingDragged != nil &&
        [self.layoutOSC isLayer:self.layoutOSC.layerBeingDragged hoveringOverButton:trashCanButton]) { // check if user wants to throw OSC button into the trash can
        // here we're going to delete something
        
        self.layoutOSC.layerBeingDragged.hidden = YES;
        
        if ([self.layoutOSC.layerBeingDragged.name isEqualToString:@"dPad"]) { // if user is hiding dPad, then hide all four dPad button child layers as well since setting the 'hidden' property on the parent dPad CALayer doesn't automatically hide the four child CALayer dPad buttons
            self.layoutOSC._upButton.hidden = YES;
            self.layoutOSC._rightButton.hidden = YES;
            self.layoutOSC._downButton.hidden = YES;
            self.layoutOSC._leftButton.hidden = YES;
        }
        
        /* if user is hiding left or right analog sticks, then hide their corresponding inner analog stick child layers as well since setting the 'hidden' property on the parent analog stick doesn't automatically hide its child inner analog stick CALayer */
        if ([self.layoutOSC.layerBeingDragged.name isEqualToString:@"leftStickBackground"]) {
            self.layoutOSC._leftStick.hidden = YES;
        }
        if ([self.layoutOSC.layerBeingDragged.name isEqualToString:@"rightStickBackground"]) {
            self.layoutOSC._rightStick.hidden = YES;
        }
    }
    [self.layoutOSC touchesEnded:touches withEvent:event];
    
    // in case of default profile OSC change, popup msgbox & remind user it's not allowed.
    if([profilesManager getIndexOfSelectedProfile] == 0 && [self.layoutOSC.layoutChanges count] > 0){
        UIAlertController * movedAlertController = [UIAlertController alertControllerWithTitle: [NSString stringWithFormat:@""] message: [LocalizationHelper localizedStringForKey:@"Layout of the Default profile can not be changed"] preferredStyle:UIAlertControllerStyleAlert];
        [movedAlertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self.oscProfilesTableViewController profileViewRefresh];
        }]];
        [self presentViewController:movedAlertController animated:YES completion:nil];
    }
    
    
    trashCanButton.tintColor = [UIColor colorWithRed:171.0/255.0 green:157.0/255.0 blue:255.0/255.0 alpha:1];
}

@end