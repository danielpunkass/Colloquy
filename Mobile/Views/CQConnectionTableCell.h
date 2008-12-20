@class MVChatConnection;

typedef enum {
	CQConnectionTableCellNotConnectedStatus,
	CQConnectionTableCellServerDisconnectedStatus,
	CQConnectionTableCellReconnectingStatus,
	CQConnectionTableCellConnectingStatus,
	CQConnectionTableCellConnectedStatus
} CQConnectionTableCellStatus;

@interface CQConnectionTableCell : UITableViewCell {
	UIImageView *_iconImageView;
	UIImageView *_badgeImageView;
	UILabel *_serverLabel;
	UILabel *_nicknameLabel;
	UILabel *_timeLabel;
	NSDate *_connectDate;
	CQConnectionTableCellStatus _status;
}
- (void) takeValuesFromConnection:(MVChatConnection *) connection;
- (void) updateConnectTime;

@property (nonatomic, copy) NSString *server;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, retain) NSDate *connectDate;
@property (nonatomic, assign) CQConnectionTableCellStatus status;
@end
