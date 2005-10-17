#include <stdlib.h>
#include <string.h>
#include "nanohttpd.h"

void list_add (list_t*, const void*);
void hash_set(hash_t*, char*, void*);
const void* hash_get(hash_t*, const char* );
list_t* hash_get_keys(const hash_t*);
void	hash_free(hash_t*, int,int, void(*)(void*));

short hash_get_hash(const char* key)
{
	if ( key ) return key[0];
	return 0;
}

hash_t*	hash_new()
{
	hash_t* me;
	int i;
	
	me =  ( hash_t*) malloc ( sizeof ( hash_t));
	me->slots = ( hash_item_t**) malloc ( 255 * sizeof ( hash_item_t*));
	for (i=0; i < 255; i++) 
		me->slots[i] = NULL;

	me->set = hash_set;
	me->get = hash_get;
	me->keys = hash_get_keys;
	me->delete = hash_free;	
	
	return me;
}

void hash_set ( hash_t *me, char* key, void* data)
{
	hash_item_t *item;
	int slotidx;
	hash_item_t *slot;
	
	item = ( hash_item_t*) malloc ( sizeof ( hash_item_t));
	item->next = NULL;
	item->key = key;
	item->data = data;
	
	slotidx = hash_get_hash ( key);
	slot = me->slots[slotidx];
	if ( ! slot) 
		me->slots[slotidx] = item;
	else
	{
		item->next = slot;
		me->slots[slotidx] = item;
	}
}

const void* hash_get(hash_t* me , const char* key)
{
	int slotidx;
	hash_item_t *item;
	
	slotidx = hash_get_hash(key);
	item = me->slots[slotidx];
	
	while (item)
	{
		if ( strcmp(item->key, key) == 0)
			return item->data;
		item = item->next;
	}
	
	return NULL;
}



list_t*	hash_get_keys(const hash_t *me)
{
	list_t*	list;
	int i;
	hash_item_t* item;
	
	list = list_new();
	for (i=0; i < 255; i++)
		if ( me->slots[i] !=NULL)
			for (item = me->slots[i]; item; item = item->next)
				list_add (list, strdup((char*) item->key));
			
	return list;
}

void	hash_free( hash_t *me, int free_key, int free_data, void(*free_func)(void*))
{
	int i;
	hash_item_t* item, *next;
	
	for (i=0; i < 255; i++)
	{
		item = me->slots[i];
		while (item)
		{
			if ( free_key == 1)
				free ((void*) item->key);
			
			if ((free_data == 1) && ( item->data !=NULL))
			{
				if ( free_func == NULL)
					free (item->data);
				else
					free_func(item->data);
			}
			
			next = item->next;
			free(item);
			item=next;
				
		}
	}
	
	free(me->slots);
	free (me);
	
}
