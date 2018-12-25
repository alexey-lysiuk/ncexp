// Copyright (C) 2014-2017 Michael Kazakov. Subject to GNU General Public License version 3.
#import <ThirdParty/RHPreferences/RHPreferences/RHPreferences.h>
#include <functional>

class ExternalToolsStorage;

@interface PreferencesWindowHotkeysTab : NSViewController<RHPreferencesViewControllerProtocol,
                                                            NSTableViewDataSource,
                                                            NSTableViewDelegate,
                                                            NSTextFieldDelegate>

- (id) initWithToolsStorage:(std::function<ExternalToolsStorage&()>)_tool_storage;

@end
