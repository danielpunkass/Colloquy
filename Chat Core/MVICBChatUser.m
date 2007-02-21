/*
 * Chat Core
 * ICB Protocol Support
 *
 * Copyright (c) 2006, 2007 Julio M. Merino Vidal <jmmv@NetBSD.org>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *    1. Redistributions of source code must retain the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer.
 *    2. Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer in the documentation and/or other materials
 *       provided with the distribution.
 *    3. The name of the author may not be used to endorse or promote
 *       products derived from this software without specific prior
 *       written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 * GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
 * IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "MVICBChatConnection.h"
#import "MVICBChatUser.h"

@implementation MVICBChatUser

#pragma mark Constructors and finalizers

- (id) initLocalUserWithConnection:(MVICBChatConnection *) connection {
	if( ( self = [self initWithNickname:nil andConnection:connection] ) ) {
		_type = MVChatLocalUserType;
		_uniqueIdentifier = [[[self nickname] lowercaseString] retain];
		_status = MVChatUserAvailableStatus;
	}

	return self;
}

- (id) initWithNickname:(NSString *) nickname
       andConnection:(MVICBChatConnection *) connection {
	if( ( self = [super init] ) ) {
		_connection = connection;
		_nickname = [nickname retain];
		_uniqueIdentifier = [[nickname lowercaseString] retain];
		_type = MVChatRemoteUserType;
		_status = MVChatUserAvailableStatus;
	}
	return self;
}

- (void) dealloc {
	[super dealloc];
}

#pragma mark Message handling

- (void) sendMessage:(NSAttributedString *) message
         withEncoding:(NSStringEncoding) encoding
		 asAction:(BOOL) action {
	[(MVICBChatConnection *)_connection ctsCommandPersonal:_nickname withMessage:[message string]];
}

@end
