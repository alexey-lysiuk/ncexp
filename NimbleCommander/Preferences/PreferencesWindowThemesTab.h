// Copyright (C) 2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once
#import <ThirdParty/RHPreferences/RHPreferences/RHPreferences.h>

@interface PreferencesWindowThemesTab : NSViewController <RHPreferencesViewControllerProtocol,
                                                          NSOutlineViewDelegate,
                                                          NSOutlineViewDataSource,
                                                          NSTextFieldDelegate>

@end
