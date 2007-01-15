#include <stdlib.h>
#include "nanohttpd.h"

void list_add( list_t *, const void * );
const void *list_first_elem( list_t * );
const void *list_next_elem( list_t * );
int list_remove_func( list_t *, int(*)( void *, void * ), void *, void(*)( void * ) );
void list_free( void * );
void list_free2( void * );
void list_free_func( void *, void(*)( void * ) );

list_t *list_new( void ) {
	list_t *me = (list_t *) malloc( sizeof( list_t));
	me -> data = NULL;
	me -> position = NULL;

	me -> first = list_first_elem;
	me -> next = list_next_elem;	
	me -> add = list_add;
	me -> remove_func = list_remove_func;

	me -> delete = list_free;
	me -> delete2 = list_free2;
	me -> delete_func = list_free_func;

	return me;
}

void list_add( list_t *me, const void *data ) {
	list_elem_t *elem = (list_elem_t *) malloc( sizeof( list_elem_t ) );
	elem -> next = me -> data;
	elem -> data = data;
	me -> data = elem;
}

int list_remove_func( list_t *me, int(*cmp_func)( void *, void * ), void *search, void(*free_func)( void * ) ) {
	int ret = 0;

	list_elem_t *next = NULL;
	list_elem_t *prev = NULL;
	list_elem_t *elem = me -> data;
	while( elem ) {	
		if( cmp_func( (void *) elem -> data, search) == 0 ) {
			ret++;
			if( prev ) prev -> next = elem -> next;
			else me -> data = elem -> next;

			next = elem -> next;	
			if( free_func  )
				free_func( (void *) elem -> data );
			free( elem );
			elem = next;
		} else {
			prev = elem;
			elem = elem -> next;
		}
	}

	return ret;
}

const void *list_first_elem( list_t *me ) {
	me -> position = me -> data;
	if( me -> position )
		return me -> position -> data;
	return NULL;
}

const void *list_next_elem( list_t *me ) {
	if( me -> position ) {
		me -> position = me -> position -> next;
		if( me -> position )
			return me -> position -> data;
	}

	return NULL;
}

void list_free( void *me ) {
	list_free_func( me, free );
}

void list_free2( void *me ) {
	list_free_func( me, NULL );
}

void list_free_func( void *_me, void(*free_func)( void * ) ) {
	list_t *me = (list_t *) _me;

	list_elem_t *next = NULL;
	list_elem_t *cur = me -> data;
	while( cur ) {
		next = cur -> next;
		if( free_func )
			free_func( ( void *) cur -> data );
		free( cur );
		cur = next;
	}

	free( me );
}
