// Copyright (C) 2013-2018 Michael Kazakov. Subject to GNU General Public License version 3.

#pragma once

#include <VFS/VFS_fwd.h>
#include <Config/ObjCBridge.h>
#include <Cocoa/Cocoa.h>

@class NCMainWindowController;
@class InternalViewerWindowController;
class ExternalToolsStorage;
class ThemesManager;
class ExternalEditorsStorage;
class NetworkConnectionsManager;

namespace nc {
    
    namespace utility {
        class NativeFSManager;
    }
    
    namespace core {
        class VFSInstanceManager;
        class ServicesHandler;
    }

    namespace ops {
        class AggregateProgressTracker;
    }
    
    namespace panel {
        class PanelViewLayoutsStorage;
        class FavoriteLocationsStorage;
        class ClosedPanelsHistory;
    }

}

@interface NCAppDelegate : NSObject <NSApplicationDelegate>

- (void) addInternalViewerWindow:(InternalViewerWindowController*) _wnd;
- (void) removeInternalViewerWindow:(InternalViewerWindowController*) _wnd;
- (InternalViewerWindowController*) findInternalViewerWindowForPath:(const std::string&)_path
                                                              onVFS:(const std::shared_ptr<VFSHost>&)_vfs;

/**
 * Runs a modal dialog window, which asks user if he wants to reset app settings.
 * Returns true if defaults were actually reset.
 */
- (bool) askToResetDefaults;

/** Returns all main windows currently present. */
@property (nonatomic, readonly) const std::vector<NCMainWindowController*> &mainWindowControllers;

/**
 * Equal to (NCAppDelegate*) ((NSApplication*)NSApp).delegate.
 */
+ (NCAppDelegate*) me;

/**
 * Support dir, ~/Library/Application Support/Nimble Commander/.
 * Is in Containers for Sandboxes versions
 */
@property (nonatomic, readonly) const std::string& supportDirectory;

/**
 * By default this dir is ~/Library/Application Support/Nimble Commander/Config/.
 * May change in the future.
 */
@property (nonatomic, readonly) const std::string& configDirectory;

/**
 * This dir is ~/Library/Application Support/Nimble Commander/State/.
 */
@property (nonatomic, readonly) const std::string& stateDirectory;

@property (nonatomic, readonly) NCConfigObjCBridge *config;

@property (nonatomic, readonly) ExternalToolsStorage& externalTools;

@property (nonatomic, readonly)
    const std::shared_ptr<nc::panel::PanelViewLayoutsStorage> &panelLayouts;

@property (nonatomic, readonly) ThemesManager& themesManager;

@property (nonatomic, readonly) ExternalEditorsStorage& externalEditorsStorage;

@property (nonatomic, readonly)
    const std::shared_ptr<nc::panel::FavoriteLocationsStorage>& favoriteLocationsStorage;

@property (nonatomic, readonly)
    const std::shared_ptr<NetworkConnectionsManager> &networkConnectionsManager;

@property (nonatomic, readonly) nc::ops::AggregateProgressTracker &operationsProgressTracker;

@property (nonatomic, readonly)
    const std::shared_ptr<nc::panel::ClosedPanelsHistory> &closedPanelsHistory;

@property (nonatomic, readonly)
    nc::core::VFSInstanceManager &vfsInstanceManager;

@property (nonatomic, readonly)
    nc::core::ServicesHandler &servicesHandler;

@property (nonatomic, readonly)
    nc::utility::NativeFSManager &nativeFSManager;

@end
