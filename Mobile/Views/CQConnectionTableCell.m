#import "CQConnectionTableCell.h"

#import "CQConnectionsController.h"

#import <ChatCore/MVChatConnection.h>

@implementation CQConnectionTableCell
- (id) initWithStyle:(UITableViewCellStyle) style reuseIdentifier:(NSString *) reuseIdentifier {
	if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]))
		return nil;

	_iconImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_badgeImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_serverLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_nicknameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];

	[self.contentView addSubview:_iconImageView];
	[self.contentView addSubview:_badgeImageView];
	[self.contentView addSubview:_timeLabel];
	[self.contentView addSubview:_nicknameLabel];
	[self.contentView addSubview:_serverLabel];

	_iconImageView.image = [UIImage imageNamed:@"server.png"];

	_serverLabel.font = [UIFont boldSystemFontOfSize:18.];
	_serverLabel.textColor = self.textLabel.textColor;
	_serverLabel.highlightedTextColor = self.textLabel.highlightedTextColor;

	_nicknameLabel.font = [UIFont systemFontOfSize:14.];
	_nicknameLabel.textColor = self.textLabel.textColor;
	_nicknameLabel.highlightedTextColor = self.textLabel.highlightedTextColor;

	_timeLabel.font = [UIFont systemFontOfSize:14.];
	_timeLabel.textColor = [UIColor colorWithRed:0.19607843 green:0.29803922 blue:0.84313725 alpha:1.];
	_timeLabel.highlightedTextColor = self.textLabel.highlightedTextColor;

	return self;
}

- (void) dealloc {
	[_iconImageView release];
	[_badgeImageView release];
	[_serverLabel release];
	[_nicknameLabel release];
	[_timeLabel release];
	[_connectDate release];

	[super dealloc];
}

#pragma mark -

- (void) takeValuesFromConnection:(MVChatConnection *) connection {
	self.server = connection.displayName;
	self.nickname = connection.nickname;

	if (connection.waitingToReconnect && connection.status != MVChatConnectionConnectingStatus)
		self.connectDate = connection.nextReconnectAttemptDate;
	else self.connectDate = connection.connectedDate;

	switch (connection.status) {
	case MVChatConnectionDisconnectedStatus:
		if (connection.waitingToReconnect)
			self.status = CQConnectionTableCellReconnectingStatus;
		else self.status = CQConnectionTableCellNotConnectedStatus;
		break;
	case MVChatConnectionServerDisconnectedStatus:
		if (connection.waitingToReconnect)
			self.status = CQConnectionTableCellReconnectingStatus;
		else self.status = CQConnectionTableCellServerDisconnectedStatus;
		break;
	case MVChatConnectionConnectingStatus:
		self.status = CQConnectionTableCellConnectingStatus;
		break;
	case MVChatConnectionConnectedStatus:
		self.status = CQConnectionTableCellConnectedStatus;
		break;
	case MVChatConnectionSuspendedStatus:
		self.status = CQConnectionTableCellReconnectingStatus;
		break;
	}

	if (connection.bouncerType == MVChatConnectionColloquyBouncer)
		_iconImageView.image = [UIImage imageNamed:@"bouncer.png"];
	else _iconImageView.image = [UIImage imageNamed:@"server.png"];
}

- (NSString *) server {
	return _serverLabel.text;
}

- (void) setServer:(NSString *) server {
	_serverLabel.text = server;

	self.accessibilityLabel = server;
}

- (NSString *) nickname {
	return _nicknameLabel.text;
}

- (void) setNickname:(NSString *) nickname {
	_nicknameLabel.text = nickname;
}

- (void) updateConnectTime {
	NSString *newTime = nil;

	if (_connectDate) {
		NSTimeInterval interval = [_connectDate timeIntervalSinceNow];
		unsigned absoluteInterval = ABS(interval);
		unsigned seconds = (absoluteInterval % 60);
		unsigned minutes = ((absoluteInterval / 60) % 60);
		unsigned hours = (absoluteInterval / 3600);

		if (interval >= 1.) {
			if (hours) newTime = [[NSString alloc] initWithFormat:NSLocalizedString(@"-%u:%02u:%02u", @"Countdown time format with hours, minutes and seconds"), hours, minutes, seconds];
			else newTime = [[NSString alloc] initWithFormat:NSLocalizedString(@"-%u:%02u", @"Countdown time format with minutes and seconds"), minutes, seconds];
		} else {
			if (hours) newTime = [[NSString alloc] initWithFormat:NSLocalizedString(@"%u:%02u:%02u", @"Countup time format with hours, minutes and seconds"), hours, minutes, seconds];
			else newTime = [[NSString alloc] initWithFormat:NSLocalizedString(@"%u:%02u", @"Countup time format with minutes and seconds"), minutes, seconds];
		}
	}

	if ([_timeLabel.text isEqualToString:newTime]) {
		[newTime release];
		return;
	}

	_timeLabel.text = newTime ? newTime : @"";

	[newTime release];

	[self setNeedsLayout];
}

@synthesize connectDate = _connectDate;

- (void) setConnectDate:(NSDate *) connectDate {
	id old = _connectDate;
	_connectDate = [connectDate retain];
	[old release];

	[self updateConnectTime];
}

@synthesize status = _status;

- (void) setStatus:(CQConnectionTableCellStatus) status {
	if (_status == status)
		return;

	_status = status;

	switch (status) {
	default:
	case CQConnectionTableCellNotConnectedStatus:
		_badgeImageView.image = nil;
		break;
	case CQConnectionTableCellReconnectingStatus:
	case CQConnectionTableCellServerDisconnectedStatus:
		_badgeImageView.image = [UIImage imageNamed:@"errorBadgeDim.png"];
		break;
	case CQConnectionTableCellConnectingStatus:
		_badgeImageView.image = [UIImage imageNamed:@"connectingBadgeDim.png"];
		break;
	case CQConnectionTableCellConnectedStatus:
		_badgeImageView.image = [UIImage imageNamed:@"connectedBadgeDim.png"];
		break;
	}

	[self setNeedsLayout];
}

- (void) setEditing:(BOOL) editing animated:(BOOL) animated {
	if (animated) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationCurve:(editing ? UIViewAnimationCurveEaseIn : UIViewAnimationCurveEaseOut)];
	}

	[super setEditing:editing animated:animated];

	_timeLabel.alpha = editing ? 0. : 1.;

	if (animated)
		[UIView commitAnimations];
}

- (void) layoutSubviews {
	[super layoutSubviews];

#define ICON_LEFT_MARGIN 10.
#define ICON_RIGHT_MARGIN 10.
#define TEXT_RIGHT_MARGIN 7.

	CGRect contentRect = self.contentView.frame;

	CGRect frame = _iconImageView.frame;
	frame.size = [_iconImageView sizeThatFits:_iconImageView.bounds.size];
	frame.origin.x = ICON_LEFT_MARGIN;
	frame.origin.y = round((contentRect.size.height / 2.) - (frame.size.height / 2.));
	_iconImageView.frame = frame;

	frame = _badgeImageView.frame;
	frame.size = [_badgeImageView sizeThatFits:_badgeImageView.bounds.size];
	frame.origin.x = CGRectGetMaxX(_iconImageView.frame) - (frame.size.width / 1.5);
	frame.origin.y = CGRectGetMaxY(_iconImageView.frame) - (frame.size.height / 1.33);
	_badgeImageView.frame = frame;

	frame = _timeLabel.frame;
	frame.size = [_timeLabel sizeThatFits:_timeLabel.bounds.size];
	frame.origin.y = round((contentRect.size.height / 2.) - (frame.size.height / 2.));

	if (self.showingDeleteConfirmation || self.showsReorderControl)
		frame.origin.x = self.bounds.size.width - contentRect.origin.x;
	else if (self.editing)
		frame.origin.x = contentRect.size.width - frame.size.width;
	else
		frame.origin.x = contentRect.size.width - frame.size.width - TEXT_RIGHT_MARGIN;

	_timeLabel.frame = frame;

	frame = _serverLabel.frame;
	frame.size = [_serverLabel sizeThatFits:_serverLabel.bounds.size];
	frame.origin.x = CGRectGetMaxX(_iconImageView.frame) + ICON_RIGHT_MARGIN;
	frame.origin.y = round((contentRect.size.height / 2.) - frame.size.height + 3.);
	frame.size.width = _timeLabel.frame.origin.x - frame.origin.x - TEXT_RIGHT_MARGIN;
	_serverLabel.frame = frame;

	frame = _nicknameLabel.frame;
	frame.size = [_nicknameLabel sizeThatFits:_nicknameLabel.bounds.size];
	frame.origin.x = CGRectGetMaxX(_iconImageView.frame) + ICON_RIGHT_MARGIN;
	frame.origin.y = round(contentRect.size.height / 2.);
	frame.size.width = _timeLabel.frame.origin.x - frame.origin.x - TEXT_RIGHT_MARGIN;
	_nicknameLabel.frame = frame;
}
@end
