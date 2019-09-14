// Copyright (C) 2013-2019 Michael Kazakov. Subject to GNU General Public License version 3.
#include "../Bootstrap/AppDelegate.h"
#include "PreferencesWindowGeneralTab.h"
#include <Habanero/dispatch_cpp.h>

using namespace std::literals;

@interface PreferencesWindowGeneralTab()

@end

@implementation PreferencesWindowGeneralTab

- (id)initWithNibName:(NSString*)[[maybe_unused]] _nibNameOrNil
               bundle:(NSBundle*)_nibBundleOrNil
{
    self = [super initWithNibName:NSStringFromClass(self.class) bundle:_nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)loadView
{
    [super loadView];
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

- (IBAction)ResetToDefaults:(id)[[maybe_unused]]_sender
{
    [(NCAppDelegate*)[NSApplication sharedApplication].delegate askToResetDefaults];
}

@end
