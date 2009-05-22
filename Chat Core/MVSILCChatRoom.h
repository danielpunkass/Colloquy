#import "MVChatRoom.h"
#import "MVChatRoomPrivate.h"
#include <libsilcclient/client.h>
#include <libsilc/silcincludes.h>

@class MVSILCChatConnection;

@interface MVSILCChatRoom : MVChatRoom {
	SilcChannelEntry _channelEntry;
}
- (id) initWithChannelEntry:(SilcChannelEntry) channelEntry andConnection:(MVSILCChatConnection *) connection;

- (SilcChannelEntry) _getChannelEntry;

- (void) _setChannelUserMode:(SilcUInt32)SilcMode forUser:(MVChatUser *) user;
- (void) _removeChannelUserMode:(SilcUInt32)SilcMode forUser:(MVChatUser *) user;

- (void) updateWithChannelEntry:(SilcChannelEntry) channelEntry;
@end
