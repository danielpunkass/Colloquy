#import "CQHelpTopicsViewController.h"

#import "CQHelpTopicViewController.h"

NSString *CQHelpTopicsURLString = @"http://colloquy.mobi/help.plist";

@interface CQHelpTopicsViewController (CQHelpTopicsViewControllerPrivate)
- (void) _generateSectionsFromHelpContent:(NSArray *) help;
@end

#pragma mark -

@implementation CQHelpTopicsViewController
- (id) initWithHelpContent:(NSArray *) help {
	if (!(self = [super initWithStyle:UITableViewStyleGrouped]))
		return nil;

	self.title = NSLocalizedString(@"Help", @"Help view title");

	if (help) {
		if (help.count)
			[self _generateSectionsFromHelpContent:help];
		else [self loadDefaultHelpContent];
	} else [self loadHelpContent];

	return self;
}

- (void) dealloc {
	[_helpSections release];
	[_helpData release];

	[super dealloc];
}

#pragma mark -

- (void) loadHelpContent {
	if (_loading)
		return;

	_loading = YES;

	id old = _helpData;
	_helpData = [[NSMutableData alloc] initWithCapacity:4096];
	[old release];

	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:CQHelpTopicsURLString] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15.];
	[NSURLConnection connectionWithRequest:request delegate:self];
}

- (void) loadDefaultHelpContent {
	NSArray *help = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Help" ofType:@"plist"]];

	[self _generateSectionsFromHelpContent:help];
}

#pragma mark -

- (void) connection:(NSURLConnection *) connection didReceiveData:(NSData *) data {
	[_helpData appendData:data];
}

- (void) connectionDidFinishLoading:(NSURLConnection *) connection {
	_loading = NO;

	NSArray *help = [NSPropertyListSerialization propertyListFromData:_helpData mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];

	[_helpData release];
	_helpData = nil;

	if (help.count)
		[self _generateSectionsFromHelpContent:help];
	else [self loadDefaultHelpContent];
}

- (void) connection:(NSURLConnection *) connection didFailWithError:(NSError *) error {
	_loading = NO;

	[_helpData release];
	_helpData = nil;

	[self loadDefaultHelpContent];
}

#pragma mark -

- (NSInteger) numberOfSectionsInTableView:(UITableView *) tableView {
    return (_helpSections.count ? _helpSections.count : 1);
}

- (NSInteger) tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	if (!_helpSections.count)
		return 1;
	return ((NSArray *)[_helpSections objectAtIndex:section]).count;
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section {
	if (_helpSections.count) {
		NSArray *sectionItems = [_helpSections objectAtIndex:section];
		NSDictionary *info = [sectionItems objectAtIndex:0];
		return [info objectForKey:@"SectionHeader"];
	}

	return nil;
}

- (NSString *) tableView:(UITableView *) tableView titleForFooterInSection:(NSInteger) section {
	if (_helpSections.count) {
		NSArray *sectionItems = [_helpSections objectAtIndex:section];
		NSDictionary *info = [sectionItems lastObject];
		return [info objectForKey:@"SectionFooter"];
	}

	return nil;
}

- (UITableViewCell *) tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	if (!_helpSections.count) {
		UITableViewCell *cell = [UITableViewCell reusableTableViewCellInTableView:tableView withIdentifier:@"Updating"];
		cell.text = NSLocalizedString(@"Updating Help Topics...", @"Updating help topics label");
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		[spinner startAnimating];

		cell.accessoryView = spinner;

		[spinner release];

		return cell;
	}

	UITableViewCell *cell = [UITableViewCell reusableTableViewCellInTableView:tableView];

	NSArray *sectionItems = [_helpSections objectAtIndex:indexPath.section];
	NSDictionary *info = [sectionItems objectAtIndex:indexPath.row];

	cell.text = [info objectForKey:@"Title"];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

- (NSIndexPath *) tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	if (!_helpSections.count)
		return nil;
	return indexPath;
}

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	if (!_helpSections.count)
		return;

	NSArray *sectionItems = [_helpSections objectAtIndex:indexPath.section];
	NSDictionary *info = [sectionItems objectAtIndex:indexPath.row];

	NSString *content = [info objectForKey:@"Content"];
	if (!content.length) {
		[tableView deselectRowAtIndexPath:[tableView indexPathForSelectedRow] animated:YES];
		return;
	}

	CQHelpTopicViewController *helpTopicController = [[CQHelpTopicViewController alloc] initWithHTMLContent:content];
	helpTopicController.navigationItem.rightBarButtonItem = self.navigationItem.rightBarButtonItem;

	[self.navigationController pushViewController:helpTopicController animated:YES];

	[helpTopicController release];
}

#pragma mark -

- (void) _generateSectionsFromHelpContent:(NSArray *) help {
	id old = _helpSections;
	_helpSections = [[NSMutableArray alloc] initWithCapacity:5];
	[old release];

	NSUInteger i = 0;
	NSUInteger sectionStart = 0;

	for (id item in help) {
		if ([item isKindOfClass:[NSString class]] && [item isEqualToString:@"Space"]) {
			if (i == sectionStart)
				continue;

			NSArray *section = [help subarrayWithRange:NSMakeRange(sectionStart, (i - sectionStart))];
			[_helpSections addObject:section];

			sectionStart = (i + 1);
		}

		++i;
	}

	if (i != sectionStart) {
		NSArray *section = [help subarrayWithRange:NSMakeRange(sectionStart, (i - sectionStart))];
		[_helpSections addObject:section];
	}

	[self.tableView reloadData];
}
@end
