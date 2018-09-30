// Copyright (C) 2017 Michael Kazakov. Subject to GNU General Public License version 3.
#include "Internal.h"

namespace nc::ops {

NSBundle *Bundle()
{
    return [NSBundle mainBundle];
}

NSString *NSLocalizedString(NSString *_key, const char *_comment)
{
    return [Bundle() localizedStringForKey:_key value:@"" table:@"Localizable"];
}

}
