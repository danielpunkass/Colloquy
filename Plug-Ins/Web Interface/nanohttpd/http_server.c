
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <sys/wait.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <signal.h>

#ifdef HAVE_CONFIG_H
#	include <config.h>
#	ifdef HAVE_ERRNO_H
#		include <errno.h>
#	else
		extern int errno;
#	endif
#endif

#include "nanohttpd.h"

#define MSG_ACCEPT	0L
#define MSG_CONNECTED 1L

int     http_req_parse(http_req_t*);
void    http_server_run(http_server_t*);
void    http_server_free(void*);
const char*   http_server_get_mime(http_server_t*, const char*);
int    http_server_add_url_mapping(http_server_t*,const char* , http_server_handler);

void handle_conn ( int sock, struct sockaddr *from_addr, size_t from_addr_len, http_server_t *me)
{
	char host [ NI_MAXHOST];
	char serv [ NI_MAXSERV];
	int errcode;
	http_resp_t	*resp;
	http_req_t*	req;

#ifdef LOG_HTTP
	int errcode = getnameinfo( from_addr, from_addr_len, host, NI_MAXHOST, serv, NI_MAXSERV, 0);
	if ( errcode) http_log (LOG_ERR, "getnameinfo(): %s", gai_strerror(errcode));
	http_log(LOG_INFO, "Connection from %s:%s", host, serv);
#endif

	req = http_req_new(sock);
	resp = http_resp_new(sock, req);
	
	if ( http_req_parse(req) == 0)
	{
		http_server_handler handler = NULL;
		url_map_t*	url_map;

		for (url_map = (url_map_t*) me->url_mappings->first(me->url_mappings); url_map;
			 url_map = (url_map_t*)	me->url_mappings->next(me->url_mappings)) {
			if (url_map->is_url_map(url_map, req->uri)) {
				handler = url_map->handler;
				break;
			}
		}

		if ( handler != NULL)	
			handler(req,resp,me);
		else 
		{
			if ( req->file_name[ (int)strlen(req->file_name) -1] =='/')
				mod_dir(req,resp, me);
			else mod_file(req, resp, me);
		}
	}

	req->delete(req);
	resp->delete(resp);	
}

http_server_t* http_server_new(char* host, char* svc)
{
	http_server_t*	me;
	
	me = ( http_server_t*) malloc ( sizeof ( http_server_t));
	me->host = host;
	me->svc = svc;
	me->sock = 0;

	me->document_root = NULL;
	me->mime_types = NULL;
	me->directory_index = NULL;

	me->running = 1;
	me->initial_process = 3;
	me->nb_process = 0;

	me->url_mappings = list_new();
	me->add_url = http_server_add_url_mapping;
	me->delete = http_server_free;
	me->get_mime = http_server_get_mime;
	me->run = http_server_run;
	return me;
}

void *http_server_run_process(void* context)
{
	struct sockaddr_storage from_addr;
	socklen_t from_addr_len;
	int	from_sock;
	http_server_t*	server = (http_server_t*) context;

	signal(SIGPIPE, SIG_IGN);
	
	while ( server->running ) 
	{
		from_addr_len = sizeof ( struct sockaddr_storage);
		from_sock = accept ( server->sock, (struct sockaddr*) &from_addr, &from_addr_len);
		if( ! server->running ) break;

#ifdef LOG_HTTP
		http_log(LOG_DEBUG, "[Process %i] accepting connection", getpid());
#endif
		handle_conn( from_sock, (struct sockaddr*) &from_addr, from_addr_len, server);
		close (from_sock);
	}

	return NULL;
}

void http_server_fork_process ( http_server_t* me, int count)
{
	int i;

	for (i = 0; i < count; i++)
	{
		pthread_attr_t attr;
		pthread_t tid;
		pthread_attr_init( &attr );
		pthread_attr_setscope( &attr, PTHREAD_SCOPE_SYSTEM );
		pthread_attr_setdetachstate( &attr, PTHREAD_CREATE_DETACHED );
		if( ! pthread_create( &tid, &attr, http_server_run_process, (void *) me ) )
			me->nb_process++;
		pthread_attr_destroy( &attr );
	}
}

void http_server_run(http_server_t* me)
{
	char	buf[255];
	int status;
	int pid;

	struct addrinfo hints;
	struct addrinfo	*res;
	int errcode;
	int un=1;

	bzero ( &hints, sizeof(hints));
	hints.ai_flags = AI_PASSIVE | AI_CANONNAME;
	hints.ai_family = PF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_protocol = 0;
	
	errcode = getaddrinfo ( me->host, me->svc, &hints, &res);
	if ( errcode != 0 || ! res ) {
#ifdef LOG_HTTP
		http_log(LOG_ERR, "getaddrinfo(), errcode=%i:", errcode, gai_strerror(errcode));
#endif
		return;
	}
	
	me->sock = socket( res->ai_family, res->ai_socktype, res->ai_protocol);
	if ( me->sock < 0)
	{
#ifdef LOG_HTTP
		http_log_perror(LOG_ERR, "socket()");
#endif
		return;
	}

	setsockopt(me->sock, SOL_SOCKET, SO_REUSEADDR, &un, sizeof(un));

	if ( bind ( me->sock, res->ai_addr, res->ai_addrlen) < 0)
	{
#ifdef LOG_HTTP
		http_log_perror(LOG_ERR, "bind()");
#endif
		return;
	}

	listen ( me->sock, 5);

#ifdef LOG_HTTP
	http_log ( LOG_INFO, "Listen on %s", res->ai_canonname);
#endif

	freeaddrinfo( res );

	http_server_fork_process ( me, me->initial_process);
}

const char*	http_server_get_mime(http_server_t* me, const char* ext)
{
	if ( ! me->mime_types)
		return NULL;
		
	return me->mime_types->get (me->mime_types, ext);
}

int	http_server_add_url_mapping(http_server_t* me, const char* url, http_server_handler handler)
{
	url_map_t* url_map;
	
	url_map = url_map_new(url, handler);
	if ( ! url_map)
		return -1;
	
	me->url_mappings->add ( me->url_mappings, url_map);	
	return 0;
}

void http_server_free(void* _me)
{
	http_server_t* me = (http_server_t*)_me;
	
	me -> running = 0;
	close( me->sock );

	if ( me->mime_types)
		me->mime_types->delete( me->mime_types, 0, 0, NULL);

	if( me->url_mappings)
		me->url_mappings->delete_func( me->url_mappings, url_map_free );

	free(me);
}