#define MODULE_NAME "MVSILCFileTransfer"

#import "MVSILCFileTransfer.h"
#import "MVSILCChatConnection.h"
#import "MVChatUser.h"
#import "NSNotificationAdditions.h"

#pragma mark -

@interface MVFileTransfer (MVFileTransferSilcPrivate)
- (void) _silcPostError:(SilcClientFileError) error;
@end

#pragma mark -

void silc_client_file_monitor ( SilcClient client, SilcClientConnection conn, SilcClientMonitorStatus status,
								SilcClientFileError error, SilcUInt64 offset, SilcUInt64 filesize,
								SilcClientEntry client_entry, SilcUInt32 session_id, const char *filepath,
								void *context ) {
	MVFileTransfer *transfer = context;
	
	switch ( status ) {
		case SILC_CLIENT_FILE_MONITOR_KEY_AGREEMENT:
			[transfer _setStatus:MVFileTransferNormalStatus];
			
			NSNotification *note = [NSNotification notificationWithName:MVFileTransferStartedNotification object:transfer];		
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThread:note];
			
			[transfer setStartDate:[NSDate date]];
			break;
			
		case SILC_CLIENT_FILE_MONITOR_SEND:
		case SILC_CLIENT_FILE_MONITOR_RECEIVE:
			[transfer setFinalSize:filesize];
			[transfer setTransfered:offset];
			
			if ( filesize == offset ) {
				 [transfer _setStatus:MVFileTransferDoneStatus];
				 NSNotification *note = [NSNotification notificationWithName:MVFileTransferFinishedNotification object:transfer];		
				 [[NSNotificationCenter defaultCenter] postNotificationOnMainThread:note];
			}
			break;

		case SILC_CLIENT_FILE_MONITOR_CLOSED:
			break;
			
		case SILC_CLIENT_FILE_MONITOR_ERROR:
			[transfer _silcPostError:error];
			break;
			
		case SILC_CLIENT_FILE_MONITOR_GET:
		case SILC_CLIENT_FILE_MONITOR_PUT:
			break;
	}
}

#pragma mark -

@implementation MVFileTransfer (MVFileTransferSilcPrivate)
- (void) _silcPostError:(SilcClientFileError) error {
	switch ( error ) {
		case SILC_CLIENT_FILE_UNKNOWN_SESSION:
		case SILC_CLIENT_FILE_ERROR: {
			NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:@"The file transfer terminated unexpectedly.", NSLocalizedDescriptionKey, nil];
			NSError *error = [NSError errorWithDomain:MVFileTransferErrorDomain code:MVFileTransferUnexpectedlyEndedError userInfo:info];
			[self performSelectorOnMainThread:@selector( _postError: ) withObject:error waitUntilDone:NO];
		}	break;
			
		case SILC_CLIENT_FILE_ALREADY_STARTED: {
			NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:@"The file %@ is already being offerend to %@.", NSLocalizedDescriptionKey, nil];
			NSError *error = [NSError errorWithDomain:MVFileTransferErrorDomain code:MVFileTransferAlreadyExistsError userInfo:info];
			[self performSelectorOnMainThread:@selector( _postError: ) withObject:error waitUntilDone:NO];
		}	break;
			
		case SILC_CLIENT_FILE_NO_SUCH_FILE:
		case SILC_CLIENT_FILE_PERMISSION_DENIED: {
			NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:@"The file %@ could not be created, please make sure you have write permissions in the %@ folder.", NSLocalizedDescriptionKey, nil];
			NSError *error = [NSError errorWithDomain:MVFileTransferErrorDomain code:MVFileTransferFileCreationError userInfo:info];
			[self performSelectorOnMainThread:@selector( _postError: ) withObject:error waitUntilDone:NO];
		}	break;
			
		case SILC_CLIENT_FILE_KEY_AGREEMENT_FAILED: {
			NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:@"Key agreement failed. Either your key was rejected by the other user or some other error happend during key negotiation.", NSLocalizedDescriptionKey, nil];
			NSError *error = [NSError errorWithDomain:MVFileTransferErrorDomain code:MVFileTransferKeyAgreementError userInfo:info];
			[self performSelectorOnMainThread:@selector( _postError: ) withObject:error waitUntilDone:NO];
		}	break;
			
		case SILC_CLIENT_FILE_OK:
			break;
	}
}
@end

#pragma mark -

@implementation MVSILCUploadFileTransfer
+ (void) initialize {
	[super initialize];
}

+ (id) transferWithSourceFile:(NSString *) path toUser:(MVChatUser *) user passively:(BOOL) passive {
	NSURL *url = [NSURL URLWithString:@"http://colloquy.info/ip.php"];
	NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:3.];
	NSMutableData *result = [[[NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:NULL] mutableCopy] autorelease];
	[result appendBytes:"\0" length:1];

	MVSILCUploadFileTransfer *transfer = [[MVSILCUploadFileTransfer alloc] initWithSessionID:0 toUser:user];
	transfer -> _source = [[path stringByStandardizingPath] copyWithZone:[self zone]];
	
	SilcClientID *clientID = silc_id_str2id( [(NSData *)[user uniqueIdentifier] bytes], [(NSData *)[user uniqueIdentifier] length], SILC_ID_CLIENT );
	if( clientID ) {
		[[[user connection] _silcClientLock] lock];
		SilcClientEntry client = silc_client_get_client_by_id( [[user connection] _silcClient], [[user connection] _silcConn], clientID );
		if( client ) {
			SilcUInt32 sessionid;
			SilcClientFileError error = silc_client_file_send( [[user connection] _silcClient], [[user connection] _silcConn], silc_client_file_monitor, transfer, [result bytes], 0, passive, client, [path fileSystemRepresentation], &sessionid);
			if (error != SILC_CLIENT_FILE_OK) {
				[transfer _silcPostError:error];
				[[[user connection] _silcClientLock] unlock];
				return nil;
			}
			
			[transfer _setSessionID:sessionid];
		}
		[[[user connection] _silcClientLock] unlock];
	} else {
		return nil;
	}

	return transfer;
}

#pragma mark -

- (id) initWithSessionID:(SilcUInt32) sessionID toUser:(MVChatUser *) user {
	if ( ( self = [self initWithUser:user] ) ) {
		[self _setSessionID:sessionID];
	}
	
	return self;
}

#pragma mark -

- (void) cancel {
	[self _setStatus:MVFileTransferStoppedStatus];
	
	[[[[self user] connection] _silcClientLock] lock];
	silc_client_file_close( [[[self user] connection] _silcClient], [[[self user] connection] _silcConn], [self _sessionID] );
	[[[[self user] connection] _silcClientLock] unlock];
}
@end

#pragma mark -

@implementation MVSILCUploadFileTransfer (MVSILCUploadFileTransferPrivate)
- (SilcUInt32) _sessionID {
	return _sessionID;
}

- (void) _setSessionID:(SilcUInt32) sessionID {
	_sessionID = sessionID;
}

@end

#pragma mark -

@implementation MVSILCDownloadFileTransfer
+ (void) initialize {
	[super initialize];
}

#pragma mark -

- (id) initWithSessionID:(SilcUInt32) sessionID toUser:(MVChatUser *) user {
	if ( ( self = [self initWithUser:user] ) ) {
		[self _setSessionID:sessionID];
	}

	return self;
}

#pragma mark -

- (void) reject {
	[[[[self user] connection] _silcClientLock] lock];
	silc_client_file_close( [[[self user] connection] _silcClient], [[[self user] connection] _silcConn], [self _sessionID] );
	[[[[self user] connection] _silcClientLock] unlock];
}

- (void) cancel {
	[[[[self user] connection] _silcClientLock] lock];
	silc_client_file_close( [[[self user] connection] _silcClient], [[[self user] connection] _silcConn], [self _sessionID] );
	[[[[self user] connection] _silcClientLock] unlock];
}

#pragma mark -

- (void) accept {
	[self acceptByResumingIfPossible:YES];
}

- (void) acceptByResumingIfPossible:(BOOL) resume {
	if( ! [[NSFileManager defaultManager] isReadableFileAtPath:[self destination]] )
		resume = NO;
}
@end

#pragma mark -

@implementation MVSILCDownloadFileTransfer (MVSILCDownloadFileTransferPrivate)
- (SilcUInt32) _sessionID {
	return _sessionID;
}

- (void) _setSessionID:(SilcUInt32) sessionID {
	_sessionID = sessionID;
}

@end