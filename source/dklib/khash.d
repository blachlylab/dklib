module dklib.khash;

import std.traits : isNumeric;
import core.stdc.stdint;    // uint32_t, etc.

/*!
  @header

  Generic hash table library.
 */

enum AC_VERSION_KHASH_H = "0.2.8";

import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.limits;

/* compiler specific configuration */

alias khint32_t = uint;

alias khint64_t = ulong;

alias khint_t = khint32_t;
alias khiter_t = khint_t;

pragma(inline, true)
{
    /// bucket empty?
    auto __ac_isempty(T)(const(khint32_t)* flag, T i)
    {
        return ((flag[i >> 4] >> ((i & 0xfU) << 1)) & 2);
    }

    /// bucket deleted?
    auto __ac_isdel(T)(const(khint32_t)* flag, T i)
    {
        return ((flag[i >> 4] >> ((i & 0xfU) << 1)) & 1);
    }

    /// bucket empty OR deleted?
    auto __ac_iseither(T)(const(khint32_t)* flag, T i)
    {
        return ((flag[i >> 4] >> ((i & 0xfU) << 1)) & 3);
    }

    /// unmark deleted
    void __ac_set_isdel_false(T)(khint32_t* flag, T i)
    {
        flag[i >> 4] &= ~(1uL << ((i & 0xfU) << 1));
    }

    /// unmark empty
    void __ac_set_isempty_false(T)(khint32_t* flag, T i)
    {
        flag[i >> 4] &= ~(2uL << ((i & 0xfU) << 1));
    }

    /// mark neither empty nor deleted
    void __ac_set_isboth_false(T)(khint32_t* flag, T i)
    {
        flag[i >> 4] &= ~(3uL << ((i & 0xfU) << 1));
    }

    /// mark deleted
    void __ac_set_isdel_true(T)(khint32_t* flag, T i)
    {
        flag[i >> 4] |= 1uL << ((i & 0xfU) << 1);
    }

    auto __ac_fsize(T)(T m)
    {
        return ((m) < 16 ? 1 : (m) >> 4);
    }

    void kroundup32(T)(ref T x)
    {
        (--(x), (x) |= (x) >> 1, (x) |= (x) >> 2, (x) |= (x) >> 4,
            (x) |= (x) >> 8, (x) |= (x) >> 16, ++(x));
    }
}

alias kcalloc = calloc;

alias kmalloc = malloc;

alias krealloc = realloc;

alias kfree = free;

private const double __ac_HASH_UPPER = 0.77;

/// Straight port of khash's generic C approach
template khash(KT, VT, bool kh_is_map = true)
{
    alias __hash_func = kh_hash!KT.kh_hash_func;
    alias __hash_equal= kh_hash!KT.kh_hash_equal;

    alias kh_t = khash; /// klib uses 'kh_t' struct name

    struct khash        // @suppress(dscanner.style.phobos_naming_convention)
    {
        khint_t n_buckets, size, n_occupied, upper_bound;
        khint32_t* flags;
        KT* keys;
        VT* vals;

        ~this()
        {
            kfree(cast(void*) this.keys);
            kfree(cast(void*) this.flags);
            kfree(cast(void*) this.vals);
        }
        
        /// Lookup by key
        ref VT opIndex(KT key)
        {
            auto x = kh_get(&this, key);
            return this.vals[x];
        }

        /// Assign by key
        void opIndexAssign(VT val, KT key)
        {
            int absent;
            //auto x = khash!(uint, char).kh_put(&this, key, &absent);
            auto x = kh_put(&this, key, &absent);
            //khash!(uint, char).kh_value(kh, k) = 10;
            this.vals[x] = val;
        }

        /// remove key/value pair
        void remove(KT key)
        {
            auto x = kh_get(&this, key);
            kh_del(&this, x);
        }

        /// Return an InputRange over the keys.
        /// Manipulating the hash table during iteration results in undefined behavior.
        /// Returns: Voldemort type
        auto byKey()
        {
            /** Manipulating the hash table during iteration results in undefined behavior */
            struct KeyRange
            {
                kh_t* kh;
                khint_t itr;
                bool empty()    // non-const as may call popFront
                {
                    //return (this.itr == kh_end(this.kh));
                    if (this.itr == kh_end(this.kh)) return true;
                    // Handle the case of deleted keys
                    else if (!kh_exists(this.kh, this.itr)) {
                        while(!kh_exists(this.kh, this.itr)) {
                            this.popFront();
                            if (this.itr == kh_end(this.kh)) return true;
                        }
                        return false;
                    }
                    return false;
                }
                ref KT front()
                {
                    return kh.keys[this.itr];
                }
                void popFront()
                {
                    if(this.itr < kh_end(this.kh)) {
                        this.itr++;
                    }
                }
            }
            return KeyRange(&this);
        }
    }
  
    void kh_clear(kh_t* h);
    int kh_resize(kh_t* h, khint_t new_n_buckets);
    khint_t kh_put(kh_t* h, KT key, int* ret);
    void kh_del(kh_t* h, khint_t x);
  
    kh_t* kh_init()
    {
        return cast(kh_t*) kcalloc(1, kh_t.sizeof);
    }
  
    void kh_destroy(kh_t* h)
    {
        if (h)
        {
            kfree(cast(void*) h.keys);
            kfree(cast(void*) h.flags);
            kfree(cast(void*) h.vals);
            kfree(h);
        }
    }
  
    void kh_clear(kh_t* h)
    {
      if (h && h.flags)
      {
        memset(h.flags, 0xaa, __ac_fsize(h.n_buckets) * khint32_t.sizeof);
        h.size = h.n_occupied = 0;
      }
    }
  
    khint_t kh_get(const(kh_t)* h, KT key)
    {
        if (h.n_buckets)
        {
          khint_t k, i, last, mask, step = 0;
          mask = h.n_buckets - 1;
          k = __hash_func(key);
          i = k & mask;
          last = i;
          while (!__ac_isempty(h.flags, i) && (__ac_isdel(h.flags, i) || !__hash_equal(h.keys[i], key)))
          {
              i = (i + (++step)) & mask;
              if (i == last)
                  return h.n_buckets;
          }
          return __ac_iseither(h.flags, i) ? h.n_buckets : i;
        }
        else
            return 0;
    }

    int kh_resize(kh_t *h, khint_t new_n_buckets)
	{
        /* This function uses 0.25*n_buckets bytes of working space instead of [sizeof(key_t+val_t)+.25]*n_buckets. */
		khint32_t *new_flags = null;
		khint_t j = 1;
		{
			kroundup32(new_n_buckets);
			if (new_n_buckets < 4) new_n_buckets = 4;
			if (h.size >= cast(khint_t)(new_n_buckets * __ac_HASH_UPPER + 0.5)) j = 0;	/* requested size is too small */
			else { /* hash table size to be changed (shrink or expand); rehash */
				new_flags = cast(khint32_t*)kmalloc(__ac_fsize(new_n_buckets) * khint32_t.sizeof);
				if (!new_flags) return -1;
				memset(new_flags, 0xaa, __ac_fsize(new_n_buckets) * khint32_t.sizeof);
				if (h.n_buckets < new_n_buckets) {	/* expand */
					KT *new_keys = cast(KT*)krealloc(cast(void *)h.keys, new_n_buckets * KT.sizeof);
					if (!new_keys) { kfree(new_flags); return -1; }
					h.keys = new_keys;
					if (kh_is_map) {
						VT *new_vals = cast(VT*)krealloc(cast(void *)h.vals, new_n_buckets * VT.sizeof);
						if (!new_vals) { kfree(new_flags); return -1; }
						h.vals = new_vals;
					}
				} /* otherwise shrink */
			}
		}
		if (j) { /* rehashing is needed */
			for (j = 0; j != h.n_buckets; ++j) {
				if (__ac_iseither(h.flags, j) == 0) {
					KT key = h.keys[j];
					VT val;
					khint_t new_mask;
					new_mask = new_n_buckets - 1;
					if (kh_is_map) val = h.vals[j];
					__ac_set_isdel_true(h.flags, j);
					while (1) { /* kick-out process; sort of like in Cuckoo hashing */
						khint_t k, i, step = 0;
						k = __hash_func(key);
						i = k & new_mask;
						while (!__ac_isempty(new_flags, i)) i = (i + (++step)) & new_mask;
						__ac_set_isempty_false(new_flags, i);
						if (i < h.n_buckets && __ac_iseither(h.flags, i) == 0) { /* kick out the existing element */
							{ KT tmp = h.keys[i]; h.keys[i] = key; key = tmp; }
							if (kh_is_map) { VT tmp = h.vals[i]; h.vals[i] = val; val = tmp; }
							__ac_set_isdel_true(h.flags, i); /* mark it as deleted in the old hash table */
						} else { /* write the element and jump out of the loop */
							h.keys[i] = key;
							if (kh_is_map) h.vals[i] = val;
							break;
						}
					}
				}
			}
			if (h.n_buckets > new_n_buckets) { /* shrink the hash table */
				h.keys = cast(KT*)krealloc(cast(void *)h.keys, new_n_buckets * KT.sizeof);
				if (kh_is_map) h.vals = cast(VT*)krealloc(cast(void *)h.vals, new_n_buckets * VT.sizeof);
			}
			kfree(h.flags); /* free the working space */
			h.flags = new_flags;
			h.n_buckets = new_n_buckets;
			h.n_occupied = h.size;
			h.upper_bound = cast(khint_t)(h.n_buckets * __ac_HASH_UPPER + 0.5);
		}
		return 0;
	}

	khint_t kh_put(kh_t *h, KT key, int *ret)
	{
		khint_t x;
		if (h.n_occupied >= h.upper_bound) { /* update the hash table */
			if (h.n_buckets > (h.size<<1)) {
				if (kh_resize(h, h.n_buckets - 1) < 0) { /* clear "deleted" elements */
					*ret = -1; return h.n_buckets;
				}
			} else if (kh_resize(h, h.n_buckets + 1) < 0) { /* expand the hash table */
				*ret = -1; return h.n_buckets;
			}
		} /* TODO: to implement automatically shrinking; resize() already support shrinking */
		{
			khint_t k, i, site, last, mask = h.n_buckets - 1, step = 0;
			x = site = h.n_buckets; k = __hash_func(key); i = k & mask;
			if (__ac_isempty(h.flags, i)) x = i; /* for speed up */
			else {
				last = i;
				while (!__ac_isempty(h.flags, i) && (__ac_isdel(h.flags, i) || !__hash_equal(h.keys[i], key))) {
					if (__ac_isdel(h.flags, i)) site = i;
					i = (i + (++step)) & mask;
					if (i == last) { x = site; break; }
				}
				if (x == h.n_buckets) {
					if (__ac_isempty(h.flags, i) && site != h.n_buckets) x = site;
					else x = i;
				}
			}
		}
		if (__ac_isempty(h.flags, x)) { /* not present at all */
			h.keys[x] = key;
			__ac_set_isboth_false(h.flags, x);
			++h.size; ++h.n_occupied;
			*ret = 1;
		} else if (__ac_isdel(h.flags, x)) { /* deleted */
			h.keys[x] = key;
			__ac_set_isboth_false(h.flags, x);
			++h.size;
			*ret = 2;
		} else *ret = 0; /* Don't touch h->keys[x] if present and not deleted */
		return x;
	}

    void kh_del(kh_t *h, khint_t x)
    {
        if (x != h.n_buckets && !__ac_iseither(h.flags, x)) {
            __ac_set_isdel_true(h.flags, x);
            --h.size;
        }
    }

    auto kh_exists(const(kh_t)* h, khint_t x)
    {
        return (!__ac_iseither(h.flags, x));
    }

    auto kh_key(const(kh_t)* h, khint_t x)
    {
        return h.keys[x];
    }

    auto kh_val(const(kh_t)* h, khint_t x)
    {
        return h.vals[x];
    }

    auto kh_begin(const(kh_t)* h)
    {
        return cast(khint_t) 0;
    }

    auto kh_end(const(kh_t)* h)
    {
        return h.n_buckets;
    }

    auto kh_size(const(kh_t)* h)
    {
        return h.size;
    }

    alias kh_n_buckets = kh_end;

    alias kh_value = kh_val;

}

/** --- BEGIN OF HASH FUNCTIONS --- */
template kh_hash(T)
{
    auto kh_hash_func(T)(T key)
    if (is(T == uint) || is(T == uint32_t) || is(T == khint32_t))
    {
        return key;
    }

    bool kh_hash_equal(T)(T a, T b)
    if (isNumeric!T)
    {
        return (a == b);
    }

    auto kh_hash_func(T)(T key)
    if (is(T == ulong) || is(T == uint64_t) || is(T == khint64_t))
    {
        return cast(khint32_t) ((key)>>33^(key)^(key)<<11);
    }

    khint_t __ac_X31_hash_string(const(char)* s)
    {
        khint_t h = cast(khint_t)*s;
        if (h) for  (++s; *s; ++s) h = (h << 5) - h + cast(khint_t)*s;
        return h;
    }
    
    auto kh_hash_func(T)(T* key)
    if(is(T == char) || is(T == const(char)) || is(T == immutable(char)))
    {
        return __ac_X31_hash_string(key);
    }

    bool kh_hash_equal(T)(T* a, T* b)
    if(is(T == char) || is(T == const(char)) || is(T == immutable(char)))
    {
        return (strcmp(a, b) == 0);
    }

    auto __ac_Wang_hash(T)(T key)
    if (is(T == uint) || is(T == uint32_t) || is(T == khint32_t))
    {
        key += ~(key << 15);
        key ^=  (key >> 10);
        key +=  (key << 3);
        key ^=  (key >> 6);
        key += ~(key << 11);
        key ^=  (key >> 16);
        return key;
    }

    // TODO
    alias kh_int_hash_func2 = __ac_Wang_hash;
}

/* --- END OF HASH FUNCTIONS --- */

/* Other convenient macros... */

/*!
  @abstract Type of the hash table.
  @param  name  Name of the hash table [symbol]
 */
//#define khash_t(name) kh_##name##_t
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Initiate a hash table.
  @param  name  Name of the hash table [symbol]
  @return       Pointer to the hash table [khash_t(name)*]
 */
//#define kh_init(name) kh_init_##name()
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Destroy a hash table.
  @param  name  Name of the hash table [symbol]
  @param  h     Pointer to the hash table [khash_t(name)*]
 */
//#define kh_destroy(name, h) kh_destroy_##name(h)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Reset a hash table without deallocating memory.
  @param  name  Name of the hash table [symbol]
  @param  h     Pointer to the hash table [khash_t(name)*]
 */
//#define kh_clear(name, h) kh_clear_##name(h)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Resize a hash table.
  @param  name  Name of the hash table [symbol]
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  s     New size [khint_t]
 */
//#define kh_resize(name, h, s) kh_resize_##name(h, s)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Insert a key to the hash table.
  @param  name  Name of the hash table [symbol]
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  k     Key [type of keys]
  @param  r     Extra return code: -1 if the operation failed;
                0 if the key is present in the hash table;
                1 if the bucket is empty (never used); 2 if the element in
				the bucket has been deleted [int*]
  @return       Iterator to the inserted element [khint_t]
 */
//#define kh_put(name, h, k, r) kh_put_##name(h, k, r)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Retrieve a key from the hash table.
  @param  name  Name of the hash table [symbol]
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  k     Key [type of keys]
  @return       Iterator to the found element, or kh_end(h) if the element is absent [khint_t]
 */
//#define kh_get(name, h, k) kh_get_##name(h, k)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Remove a key from the hash table.
  @param  name  Name of the hash table [symbol]
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  k     Iterator to the element to be deleted [khint_t]
 */
//#define kh_del(name, h, k) kh_del_##name(h, k)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Test whether a bucket contains data.
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  x     Iterator to the bucket [khint_t]
  @return       1 if containing data; 0 otherwise [int]
 */
//#define kh_exist(h, x) (!__ac_iseither((h)->flags, (x)))
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get key given an iterator
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  x     Iterator to the bucket [khint_t]
  @return       Key [type of keys]
 */
//#define kh_key(h, x) ((h)->keys[x])
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get value given an iterator
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  x     Iterator to the bucket [khint_t]
  @return       Value [type of values]
  @discussion   For hash sets, calling this results in segfault.
 */
//#define kh_val(h, x) ((h)->vals[x])
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Alias of kh_val()
 */
//#define kh_value(h, x) ((h)->vals[x])
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get the start iterator
  @param  h     Pointer to the hash table [khash_t(name)*]
  @return       The start iterator [khint_t]
 */
//#define kh_begin(h) (khint_t)(0)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get the end iterator
  @param  h     Pointer to the hash table [khash_t(name)*]
  @return       The end iterator [khint_t]
 */
//#define kh_end(h) ((h)->n_buckets)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get the number of elements in the hash table
  @param  h     Pointer to the hash table [khash_t(name)*]
  @return       Number of elements in the hash table [khint_t]
 */
//#define kh_size(h) ((h)->size)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get the number of buckets in the hash table
  @param  h     Pointer to the hash table [khash_t(name)*]
  @return       Number of buckets in the hash table [khint_t]
 */
//#define kh_n_buckets(h) ((h)->n_buckets)
// Moved into template khash(KT, VT)

/++ foreach: TODO

/*! @function
  @abstract     Iterate over the entries in the hash table
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  kvar  Variable to which key will be assigned
  @param  vvar  Variable to which value will be assigned
  @param  code  Block of code to execute
 */
auto kh_foreach(kh_t* h, kvar, vvar, code)
{
    khint_t __i;
    for (__i = kh_begin(h); __i != kh_end(h); ++__i) {
        if (!kh_exist(h, __i)) continue;
        kvar = kh_key(h, __i);
        vvar = kh_val(h, __i);
        code;
    }
}

/*! @function
  @abstract     Iterate over the values in the hash table
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  vvar  Variable to which value will be assigned
  @param  code  Block of code to execute
 */
 auto kh_foreach_value(kh_t* h, vvar, code)
 {
     khint_t __i;
     for (__i = kh_begin(h); __i != kh_end(h); ++__i) {
         if (!kh_exist(h, __i)) continue;
         vvar = kh_val(h, __i);
         code;
     }
 }
+/
unittest
{
    import std.stdio : writeln, writefln;

    writeln("khash unit test");

//    auto kh = khash!(uint, char).kh_init();

    //int absent;
    //auto k = khash!(uint, char).kh_put(kh, 5, &absent);
    ////khash!(uint, char).kh_value(kh, k) = 10;
    //kh.vals[k] = 'J';

//    (*kh)[5] = 'J';
//    writeln("Entry value:", (*kh)[5]);
    
//    khash!(uint, char).kh_destroy(kh);

    auto kh = khash!(uint, char)();
    kh[5] = 'J';
    writeln("Value: ", kh[5]);

    kh[1] = 'O';
    kh[99] = 'N';

    writeln("foreach by key");
    foreach(k; kh.byKey()) {
        writefln("Key: %s", k);
    }

    writeln("Now an empty hash table:");
    auto kh_empty = khash!(uint, char)();
    foreach(k; kh_empty.byKey) {
        writefln("Key: %s", k);
    }

}
