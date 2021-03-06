// Copyright (C) 2017-2018 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include <VFS/VFS.h>
#include <Cocoa/Cocoa.h>

@class PanelController;

@interface NCPanelOpenWithMenuDelegate : NSObject<NSMenuDelegate>

- (void) setContextSource:(const std::vector<VFSListingItem>)_items;
- (void) addManagedMenu:(NSMenu*)_menu;

@property (weak, nonatomic) PanelController *target;

@property (class, readonly, nonatomic) NSString *regularMenuIdentifier;
@property (class, readonly, nonatomic) NSString *alwaysOpenWithMenuIdentifier;

@end
