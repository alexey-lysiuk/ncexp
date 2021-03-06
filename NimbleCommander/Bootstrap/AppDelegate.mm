// Copyright (C) 2013-2018 Michael Kazakov. Subject to GNU General Public License version 3.
#include <Habanero/CommonPaths.h>
#include <Habanero/CFDefaultsCPP.h>
#include <Habanero/algo.h>
#include <Utility/NSMenu+Hierarchical.h>
#include <Utility/NativeFSManager.h>
#include <Utility/PathManip.h>
#include <Utility/FunctionKeysPass.h>
#include <Utility/StringExtras.h>
#include <RoutedIO/RoutedIO.h>
#include "ThirdParty/NSFileManagerDirectoryLocations/NSFileManager+DirectoryLocations.h"
#include <NimbleCommander/Core/TemporaryNativeFileStorage.h>
#include <NimbleCommander/Core/ActionsShortcutsManager.h>
#include <NimbleCommander/Core/Dock.h>
#include <NimbleCommander/Core/ServicesHandler.h>
#include <NimbleCommander/Core/ConfigBackedNetworkConnectionsManager.h>
#include <NimbleCommander/Core/ConnectionsMenuDelegate.h>
#include <NimbleCommander/Core/Theming/ThemesManager.h>
#include <NimbleCommander/States/Terminal/ShellState.h>
#include <NimbleCommander/States/MainWindowController.h>
#include <NimbleCommander/States/FilePanels/MainWindowFilePanelState.h>
#include <NimbleCommander/States/FilePanels/ExternalToolsSupport.h>
#include <NimbleCommander/States/FilePanels/ExternalEditorInfo.h>
#include <NimbleCommander/States/FilePanels/PanelViewLayoutSupport.h>
#include <NimbleCommander/States/FilePanels/FavoritesImpl.h>
#include <NimbleCommander/States/FilePanels/FavoritesWindowController.h>
#include <NimbleCommander/States/FilePanels/FavoritesMenuDelegate.h>
#include <NimbleCommander/Preferences/Preferences.h>
#include <NimbleCommander/Viewer/InternalViewerController.h>
#include <NimbleCommander/Viewer/InternalViewerWindowController.h>
#include <NimbleCommander/GeneralUI/VFSListWindowController.h>
#include <Operations/Pool.h>
#include <Operations/AggregateProgressTracker.h>
#include "AppDelegate.h"
#include <Config/ConfigImpl.h>
#include <Config/FileOverwritesStorage.h>
#include <Config/Executor.h>
#include "AppDelegate+Migration.h"
#include "ConfigWiring.h"
#include "VFSInit.h"
#include "Interactions.h"
#include <NimbleCommander/States/MainWindow.h>
#include "AppDelegate+MainWindowCreation.h"
#include <NimbleCommander/States/FilePanels/Helpers/ClosedPanelsHistoryImpl.h>
#include <NimbleCommander/States/FilePanels/Helpers/RecentlyClosedMenuDelegate.h>
#include <NimbleCommander/Core/VFSInstanceManagerImpl.h>
#include <Utility/ObjCpp.h>

using namespace std::literals;
using namespace nc::bootstrap;

static std::optional<std::string> Load(const std::string &_filepath);

static auto g_ConfigDirPostfix = @"/Config/";
static auto g_StateDirPostfix = @"/State/";

static nc::config::ConfigImpl *g_Config = nullptr;
static nc::config::ConfigImpl *g_State = nullptr;
static nc::config::ConfigImpl *g_NetworkConnectionsConfig = nullptr;

static const auto g_ConfigForceFn = "general.alwaysUseFnKeysAsFunctional";
static const auto g_ConfigExternalToolsList = "externalTools.tools_v1";
static const auto g_ConfigLayoutsList = "filePanel.layout.layouts_v1";
static const auto g_ConfigSelectedThemes = "general.theme";
static const auto g_ConfigThemesList = "themes.themes_v1";
static const auto g_ConfigExtEditorsList = "externalEditors.editors_v1";

nc::config::Config &GlobalConfig() noexcept
{
    assert(g_Config);
    return *g_Config;
}

nc::config::Config &StateConfig() noexcept
{
    assert(g_State);
    return *g_State;
}

static void ResetDefaults()
{
    const auto bundle_id = NSBundle.mainBundle.bundleIdentifier;
    [NSUserDefaults.standardUserDefaults removePersistentDomainForName:bundle_id];
    [NSUserDefaults.standardUserDefaults synchronize];
    g_Config->ResetToDefaults();
    g_State->ResetToDefaults();
    g_Config->Commit();
    g_State->Commit();
}

static void UpdateMenuItemsPlaceholders( int _tag )
{
    static const auto app_name = (NSString*)[NSBundle.mainBundle.infoDictionary
        objectForKey:@"CFBundleName"];

    if( auto menu_item = [NSApp.mainMenu itemWithTagHierarchical:_tag] ) {
        auto title = menu_item.title;
        title = [title stringByReplacingOccurrencesOfString:@"{AppName}" withString:app_name];
        menu_item.title = title;
    }
}

static void UpdateMenuItemsPlaceholders( const char *_action )
{
    UpdateMenuItemsPlaceholders( ActionsShortcutsManager::Instance().TagFromAction(_action) );
}

static void CheckDefaultsReset()
{
    const auto erase_mask = NSAlphaShiftKeyMask | NSShiftKeyMask |
                            NSAlternateKeyMask | NSCommandKeyMask;
    if( (NSEvent.modifierFlags & erase_mask) == erase_mask )
        if( AskUserToResetDefaults() ) {
            ResetDefaults();
            exit(0);
        }
}

static NCAppDelegate *g_Me = nil;

@interface NCAppDelegate()

@property (nonatomic, readonly) nc::core::Dock& dock;

@property (nonatomic) IBOutlet NSMenu *recentlyClosedMenu;

@end

@implementation NCAppDelegate
{
    std::vector<NCMainWindowController *>       m_MainWindows;
    std::vector<InternalViewerWindowController*>m_ViewerWindows;
    spinlock                                    m_ViewerWindowsLock;
    std::string         m_SupportDirectory;
    std::string         m_ConfigDirectory;
    std::string         m_StateDirectory;
    std::vector<nc::config::Token> m_ConfigObservationTickets;
    upward_flag         m_FinishedLaunching;
    std::shared_ptr<nc::panel::FavoriteLocationsStorageImpl> m_Favorites;
    NSMutableArray      *m_FilesToOpen;
}

@synthesize mainWindowControllers = m_MainWindows;
@synthesize configDirectory = m_ConfigDirectory;
@synthesize stateDirectory = m_StateDirectory;
@synthesize supportDirectory = m_SupportDirectory;

- (id) init
{
    self = [super init];
    if(self) {
        g_Me = self;
        m_FilesToOpen = [[NSMutableArray alloc] init];
        CheckDefaultsReset();
        m_SupportDirectory =
            EnsureTrailingSlash(NSFileManager.defaultManager.
                                applicationSupportDirectory.fileSystemRepresentationSafe);
        [self setupConfigs];
    }
    return self;
}

+ (NCAppDelegate*) me
{
    return g_Me;
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    RegisterAvailableVFS();
    
    nc::utility::NativeFSManager::Instance();
    [self themesManager];
    [self favoriteLocationsStorage];
    
    [self updateMainMenuFeaturesByVersionAndState];
    
    // update menu with current shortcuts layout
    ActionsShortcutsManager::Instance().SetMenuShortCuts([NSApp mainMenu]);
    
    [self wireMenuDelegates];
        }

- (void) wireMenuDelegates
{
    // set up menu delegates. do this via DI to reduce links to AppDelegate in whole codebase
    auto item_for_action = [](const char *_action){
        auto tag = ActionsShortcutsManager::Instance().TagFromAction(_action);
        return [NSApp.mainMenu itemWithTagHierarchical:tag];
    };
    
    static auto layouts_delegate = [[PanelViewLayoutsMenuDelegate alloc]
                                    initWithStorage:*self.panelLayouts];
    item_for_action("menu.view.toggle_layout_1").menu.delegate = layouts_delegate;

    auto manage_fav_item = item_for_action("menu.go.favorites.manage");
    static auto favorites_delegate = [[FavoriteLocationsMenuDelegate alloc]
                                      initWithStorage:*self.favoriteLocationsStorage
                                      andManageMenuItem:manage_fav_item];
    manage_fav_item.menu.delegate = favorites_delegate;
  
    auto clear_freq_item = [NSApp.mainMenu itemWithTagHierarchical:14220];
    static auto frequent_delegate = [[FrequentlyVisitedLocationsMenuDelegate alloc]
        initWithStorage:*self.favoriteLocationsStorage andClearMenuItem:clear_freq_item];
    clear_freq_item.menu.delegate = frequent_delegate;
    
    const auto connections_menu_item = item_for_action("menu.go.connect.network_server");
    static const auto conn_delegate = [[ConnectionsMenuDelegate alloc] initWithManager:
        []()->NetworkConnectionsManager &{
        return *g_Me.networkConnectionsManager;
    }];
    connections_menu_item.menu.delegate = conn_delegate;
    
    auto panels_locator = []() -> MainWindowFilePanelState* {
        if( auto wnd = objc_cast<NCMainWindow>(NSApp.keyWindow) )
            if( auto ctrl = objc_cast<NCMainWindowController>(wnd.delegate) )
                return ctrl.filePanelsState;
        return nil;
    };
    static const auto recently_closed_delegate = [[NCPanelsRecentlyClosedMenuDelegate alloc]
                                                  initWithMenu:self.recentlyClosedMenu
                                                  storage:self.closedPanelsHistory
                                                  panelsLocator:panels_locator];
    (void)recently_closed_delegate;

    // These menus will have a submenu generated on the fly by according actions.
    // However, it's required for these menu items to always have submenus so that 
    // Preferences can detect it and mark its hotkeys as readonly.
    // This solution is horrible but I can find a better one right now.
    item_for_action("menu.file.open_with_submenu").submenu = [NSMenu new];
    item_for_action("menu.file.always_open_with_submenu").submenu = [NSMenu new];
}

- (void)updateMainMenuFeaturesByVersionAndState
{
    static NSMenu *original_menu_state = [NSApp.mainMenu copy];
    
    // disable some features available in menu by configuration limitation
    auto tag_from_lit       = [ ](const char *s) { return ActionsShortcutsManager::Instance().TagFromAction(s);             };
    auto current_menuitem   = [&](const char *s) { return [NSApp.mainMenu itemWithTagHierarchical:tag_from_lit(s)];         };
    auto initial_menuitem   = [&](const char *s) { return [original_menu_state itemWithTagHierarchical:tag_from_lit(s)];    };
    auto hide               = [&](const char *s) {
        auto item = current_menuitem(s);
        item.alternate = false;
        item.hidden = true;
    };
    auto enable             = [&](const char *_action, bool _enabled) {
        current_menuitem(_action).action = _enabled ? initial_menuitem(_action).action : nil;
    };
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    m_FinishedLaunching.toggle();
    
    if( self.mainWindowControllers.empty() )
        [self applicationOpenUntitledFile:NSApp]; // if there's no restored windows - we'll create a freshly new one
    
    NSApp.servicesProvider = self;
    [NSApp registerServicesMenuSendTypes:@[NSFilenamesPboardType, (__bridge NSString *)kUTTypeFileURL]
                             returnTypes:@[]]; // pasteboard types provided by PanelController
    NSUpdateDynamicServices();
    
    // Since we have different app names (Nimble Commander and Nimble Commander Pro) and one
    // fixed menu, we have to emplace the right title upon startup in some menu elements.
    UpdateMenuItemsPlaceholders( "menu.nimble_commander.about" );
    UpdateMenuItemsPlaceholders( "menu.nimble_commander.hide" );
    UpdateMenuItemsPlaceholders( "menu.nimble_commander.quit" );
    UpdateMenuItemsPlaceholders( 17000 ); // Menu->Help
    
    // calling modules running in background
    TemporaryNativeFileStorage::Instance(); // starting background purging implicitly
    
    ConfigWiring{GlobalConfig()}.Wire();
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:nil];
}

- (void) setupConfigs
{
    assert( g_Config == nullptr && g_State == nullptr );
    auto fm = NSFileManager.defaultManager;

    NSString *config = [fm.applicationSupportDirectory stringByAppendingString:g_ConfigDirPostfix];
    if( ![fm fileExistsAtPath:config] )
        [fm createDirectoryAtPath:config withIntermediateDirectories:true attributes:nil error:nil];
    m_ConfigDirectory = config.fileSystemRepresentationSafe;
    
    NSString *state = [fm.applicationSupportDirectory stringByAppendingString:g_StateDirPostfix];
    if( ![fm fileExistsAtPath:state] )
        [fm createDirectoryAtPath:state withIntermediateDirectories:true attributes:nil error:nil];
    m_StateDirectory = state.fileSystemRepresentationSafe;
    
    const auto bundle = NSBundle.mainBundle;
    const auto config_defaults_path = [bundle pathForResource:@"Config"
                                                       ofType:@"json"].fileSystemRepresentationSafe;
    const auto config_defaults = Load(config_defaults_path);
    if( config_defaults == std::nullopt ) {
        std::cerr << "Failed to read the main config file: " << config_defaults_path << std::endl;
        exit(0);
    }
        
    const auto state_defaults_path = [bundle pathForResource:@"State"
                                                      ofType:@"json"].fileSystemRepresentationSafe;
    const auto state_defaults = Load(state_defaults_path);
    if( state_defaults == std::nullopt ) {
        std::cerr << "Failed to read the state config file: " << state_defaults_path << std::endl;
        exit(0);
    }
    
    const auto write_delay = std::chrono::seconds{30};
    const auto reload_delay = std::chrono::seconds{1};
    
    g_Config = new nc::config::ConfigImpl
    (*config_defaults,
     std::make_shared<nc::config::FileOverwritesStorage>(self.configDirectory + "Config.json"),
     std::make_shared<nc::config::DelayedAsyncExecutor>(write_delay),
     std::make_shared<nc::config::DelayedAsyncExecutor>(reload_delay));
    
    g_State = new nc::config::ConfigImpl
    (*state_defaults,
     std::make_shared<nc::config::FileOverwritesStorage>(self.stateDirectory + "State.json"),
     std::make_shared<nc::config::DelayedAsyncExecutor>(write_delay),
     std::make_shared<nc::config::DelayedAsyncExecutor>(reload_delay));    

    g_NetworkConnectionsConfig = new nc::config::ConfigImpl
    ("",
     std::make_shared<nc::config::FileOverwritesStorage>(self.configDirectory + 
                                                         "NetworkConnections.json"),
     std::make_shared<nc::config::DelayedAsyncExecutor>(write_delay),
     std::make_shared<nc::config::DelayedAsyncExecutor>(reload_delay));    
    
    atexit([]{
        // this callback is quite brutal, but works well. may need to find some more gentle approach
        g_Config->Commit();
        g_State->Commit();
        g_NetworkConnectionsConfig->Commit();
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return NO;
}

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    NSWindow *window = nil;
    if( [identifier isEqualToString:NCMainWindow.defaultIdentifier] )
        window = [g_Me allocateMainWindowRestoredBySystem].window;
    completionHandler(window, nil);
}

- (IBAction)onMainMenuNewWindow:(id)sender
{
    auto ctrl = [self allocateMainWindowRestoredManually];
    [ctrl showWindow:self];
}

- (void) addMainWindow:(NCMainWindowController*) _wnd
{
    m_MainWindows.push_back(_wnd);
}

- (void) removeMainWindow:(NCMainWindowController*) _wnd
{
    auto it = find(begin(m_MainWindows), end(m_MainWindows), _wnd);
    if(it != end(m_MainWindows))
        m_MainWindows.erase(it);
}

- (void)windowWillClose:(NSNotification*)aNotification
{
    if( auto main_wnd = objc_cast<NCMainWindow>(aNotification.object) )
        if( auto main_ctrl = objc_cast<NCMainWindowController>(main_wnd.delegate) ) {
            dispatch_to_main_queue([=]{
                [self removeMainWindow:main_ctrl];
            });
        }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    bool has_running_ops = false;
    auto controllers = self.mainWindowControllers;
    for( const auto &wincont: controllers )
        if( !wincont.operationsPool.Empty() ) {
            has_running_ops = true;
            break;
        }
        else if(wincont.terminalState && wincont.terminalState.isAnythingRunning) {
            has_running_ops = true;
            break;
        }
    
    if( has_running_ops ) {
        if( !AskToExitWithRunningOperations() )
            return NSTerminateCancel;

        for( const auto &wincont : controllers ) {
            wincont.operationsPool.StopAndWaitForShutdown();
            [wincont.terminalState terminate];
        }
    }
    
    // last cleanup before shutting down here:
    if( m_Favorites  )
        m_Favorites->StoreData( StateConfig(), "filePanel.favorites" );
    
    return NSTerminateNow;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return true;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    if( !m_FinishedLaunching )
        return false;
    
    if( !self.mainWindowControllers.empty() )
        return true;
  
    [self onMainMenuNewWindow:sender];
    
    return true;
}


- (void)drainFilesToOpen
{
    if( m_FilesToOpen.count == 0 )
        return;

        self.servicesHandler.OpenFiles(m_FilesToOpen);

    [m_FilesToOpen removeAllObjects];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    [m_FilesToOpen addObjectsFromArray:@[filename]];
    dispatch_to_main_queue_after(250ms, []{ [g_Me drainFilesToOpen]; });
    return true;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames
{
    [m_FilesToOpen addObjectsFromArray:filenames];
    dispatch_to_main_queue_after(250ms, []{ [g_Me drainFilesToOpen]; });
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)openFolderService:(NSPasteboard *)pboard userData:(NSString *)data error:(__strong NSString **)error
{
    self.servicesHandler.OpenFolder(pboard, data, error);
}

- (void)revealItemService:(NSPasteboard *)pboard userData:(NSString *)data error:(__strong NSString **)error
{
    self.servicesHandler.RevealItem(pboard, data, error);
}

- (void)OnPreferencesCommand:(id)sender
{
    ShowPreferencesWindow();
}

- (IBAction)OnShowHelp:(id)sender
{
    const auto url = [NSBundle.mainBundle URLForResource:@"Help" withExtension:@"pdf"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (IBAction)OnMenuToggleAdminMode:(id)sender
{
    if( RoutedIO::Instance().Enabled() )
        RoutedIO::Instance().TurnOff();
    else {
        const auto turned_on = RoutedIO::Instance().TurnOn();
        if( !turned_on )
            WarnAboutFailingToAccessPriviledgedHelper();
    }

    self.dock.SetAdminBadge( RoutedIO::Instance().Enabled() );
}

- (BOOL) validateMenuItem:(NSMenuItem *)item
{
    auto tag = item.tag;
    
    IF_MENU_TAG("menu.nimble_commander.toggle_admin_mode") {
        bool enabled = RoutedIO::Instance().Enabled();
        item.title = enabled ?
            NSLocalizedString(@"Disable Admin Mode", "Menu item title for disabling an admin mode") :
            NSLocalizedString(@"Enable Admin Mode", "Menu item title for enabling an admin mode");
        return true;
    }
    
    return true;
}

- (NCConfigObjCBridge*) config
{
    static auto global_config_bridge = [[NCConfigObjCBridge alloc] initWithConfig:*g_Config];
    return global_config_bridge;
}

- (ExternalToolsStorage&) externalTools
{
    static auto i = new ExternalToolsStorage(g_ConfigExternalToolsList);
    return *i;
}

- (const std::shared_ptr<nc::panel::PanelViewLayoutsStorage>&) panelLayouts
{
    static auto i = std::make_shared<nc::panel::PanelViewLayoutsStorage>(g_ConfigLayoutsList);
    return i;
}

- (ThemesManager&) themesManager
{
    static auto i = new ThemesManager(g_ConfigSelectedThemes, g_ConfigThemesList);
    return *i;
}

- (ExternalEditorsStorage&) externalEditorsStorage
{
    static auto i = new ExternalEditorsStorage(g_ConfigExtEditorsList);
    return *i;
}

- (const std::shared_ptr<nc::panel::FavoriteLocationsStorage>&) favoriteLocationsStorage
{
    static std::once_flag once;
    std::call_once(once, [&]{
        using t = nc::panel::FavoriteLocationsStorageImpl;
        m_Favorites = std::make_shared<t>(StateConfig(), "filePanel.favorites");
    });
    
    static const std::shared_ptr<nc::panel::FavoriteLocationsStorage> inst = m_Favorites;
    return inst;
}

- (bool) askToResetDefaults
{
    if( AskUserToResetDefaults() ) {
        ResetDefaults();
        return true;
    }
    return false;
}

- (void) addInternalViewerWindow:(InternalViewerWindowController*)_wnd
{
    LOCK_GUARD(m_ViewerWindowsLock) {
        m_ViewerWindows.emplace_back(_wnd);
    }
}

- (void) removeInternalViewerWindow:(InternalViewerWindowController*)_wnd
{
    LOCK_GUARD(m_ViewerWindowsLock) {
        auto i = find(begin(m_ViewerWindows), end(m_ViewerWindows), _wnd);
        if( i != end(m_ViewerWindows) )
            m_ViewerWindows.erase(i);
    }
}

- (InternalViewerWindowController*) findInternalViewerWindowForPath:(const std::string&)_path
                                                              onVFS:(const VFSHostPtr&)_vfs
{
    LOCK_GUARD(m_ViewerWindowsLock) {
        auto i = find_if(begin(m_ViewerWindows), end(m_ViewerWindows), [&](auto v){
            return v.internalViewerController.filePath == _path &&
            v.internalViewerController.fileVFS == _vfs;
        });
        return i != end(m_ViewerWindows) ? *i : nil;
    }
    return nil;
}

- (IBAction)onMainMenuPerformShowVFSListAction:(id)sender
{
    static __weak VFSListWindowController *existing_window = nil;
    if( auto w = (VFSListWindowController*)existing_window  )
        [w show];
    else {
        auto window = [[VFSListWindowController alloc] initWithVFSManager:self.vfsInstanceManager];
        [window show];
        existing_window = window;
    }
}

- (IBAction)onMainMenuPerformShowFavorites:(id)sender
{
    static __weak FavoritesWindowController *existing_window = nil;
    if( auto w = (FavoritesWindowController*)existing_window  ) {
        [w show];
        return ;
    }
    auto storage = []()->nc::panel::FavoriteLocationsStorage& {
        return *NCAppDelegate.me.favoriteLocationsStorage;
    };
    FavoritesWindowController *window = [[FavoritesWindowController alloc]
                                         initWithFavoritesStorage:storage];
    auto provide_panel = []() -> std::vector<std::pair<VFSHostPtr, std::string>> {
        std::vector< std::pair<VFSHostPtr, std::string> > panel_paths;
        for( const auto &ctr: NCAppDelegate.me.mainWindowControllers ) {
            auto state = ctr.filePanelsState;
            auto paths = state.filePanelsCurrentPaths;
            for( const auto &p:paths )
                panel_paths.emplace_back( std::get<1>(p), std::get<0>(p) );
        }
        return panel_paths;
    };
    window.provideCurrentUniformPaths = provide_panel;
    
    [window show];
    existing_window = window;
}

- (const std::shared_ptr<NetworkConnectionsManager> &)networkConnectionsManager
{
    static const auto mgr = std::make_shared<ConfigBackedNetworkConnectionsManager>
        (*g_NetworkConnectionsConfig);
    static const std::shared_ptr<NetworkConnectionsManager> int_ptr = mgr;
    return int_ptr;
}

- (nc::ops::AggregateProgressTracker&) operationsProgressTracker
{
    static const auto apt = [self]{
        const auto apt = std::make_shared<nc::ops::AggregateProgressTracker>();
        apt->SetProgressCallback([](double _progress){
            g_Me.dock.SetProgress( _progress );
        });
        return apt;
    }();
    return *apt.get();
}

- (nc::core::Dock&) dock
{
    static const auto instance = new nc::core::Dock;
    return *instance;
}

- (nc::core::VFSInstanceManager&)vfsInstanceManager
{
    static const auto instance = new nc::core::VFSInstanceManagerImpl;
    return *instance;
}

- (const std::shared_ptr<nc::panel::ClosedPanelsHistory>&)closedPanelsHistory
{
    static const auto impl = std::make_shared<nc::panel::ClosedPanelsHistoryImpl>();
    static const std::shared_ptr<nc::panel::ClosedPanelsHistory> history = impl;
    return history;
}

- (NCMainWindowController*)windowForExternalRevealRequest
{
    NCMainWindowController *target_window = nil;
    for( NSWindow *wnd in NSApplication.sharedApplication.orderedWindows )
        if( auto wc =  objc_cast<NCMainWindowController>(wnd.windowController) )
            if( [wc.topmostState isKindOfClass:MainWindowFilePanelState.class] ) {
                target_window = wc;
                break;
            }
    
    if( !target_window )
        target_window = [self allocateDefaultMainWindow];
    
    if( target_window )
        [target_window.window makeKeyAndOrderFront:self];
    
    return target_window;
}

- (nc::core::ServicesHandler&)servicesHandler
{
    auto window_locator = []{
        return [g_Me windowForExternalRevealRequest];
    };
    static nc::core::ServicesHandler handler(window_locator);
    return handler;
}

- (nc::utility::NativeFSManager &)nativeFSManager
{
    // temporary solution:
    return nc::utility::NativeFSManager::Instance();
}

@end

static std::optional<std::string> Load(const std::string &_filepath)
{
    std::ifstream in( _filepath, std::ios::in | std::ios::binary);
    if( !in )
        return std::nullopt;        
    
    std::string contents;
    in.seekg( 0, std::ios::end );
    contents.resize( in.tellg() );
    in.seekg( 0, std::ios::beg );
    in.read( &contents[0], contents.size() );
    in.close();
    return contents;
}
