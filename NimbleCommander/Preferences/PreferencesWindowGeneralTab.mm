// Copyright (C) 2013-2017 Michael Kazakov. Subject to GNU General Public License version 3.
#include "../Bootstrap/AppDelegate.h"
#include "PreferencesWindowGeneralTab.h"

@interface PreferencesWindowGeneralTab()

@property (nonatomic) IBOutlet NSButton *FSAccessResetButton;
@property (nonatomic) IBOutlet NSTextField *FSAccessLabel;

@end

@implementation PreferencesWindowGeneralTab

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:NSStringFromClass(self.class) bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)loadView
{
    [super loadView];
	self.FSAccessResetButton.enabled = false;
    [self.view layoutSubtreeIfNeeded];    
}

-(NSString*)identifier{
    return NSStringFromClass(self.class);
}
-(NSImage*)toolbarItemImage{
    return [NSImage imageNamed:NSImageNamePreferencesGeneral];
}
-(NSString*)toolbarItemLabel{
    return NSLocalizedStringFromTable(@"General",
                                      @"Preferences",
                                      "General preferences tab title");
}

- (IBAction)ResetToDefaults:(id)sender
{
    [(NCAppDelegate*)[NSApplication sharedApplication].delegate askToResetDefaults];
}

@end
