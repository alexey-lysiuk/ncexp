// Copyright (C) 2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

namespace nc::bootstrap {

bool AskUserToResetDefaults();
bool AskUserToProvideUsageStatistics();
bool AskToExitWithRunningOperations();
void WarnAboutFailingToAccessPriviledgedHelper();
    
}
