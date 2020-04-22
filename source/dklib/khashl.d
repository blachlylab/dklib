/*  The MIT License

    Copyright (c) 2008, 2009, 2011 by Attractive Chaos <attractor@live.co.uk>
    Copyright (c) 2019 James S Blachly, MD <james.blachly@gmail.com>

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
    BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

module dklib.khashl;

import std.traits : isNumeric, isSomeString, isSigned, hasMember;
import core.stdc.stdint;    // uint32_t, etc.
import core.memory;         // GC

/*!
  @header

  Generic hash table library.
 */

enum AC_VERSION_KHASHL_H = "0.1";

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
    auto __kh_used(T)(const(khint32_t)* flag, T i)
    {
        return (flag[i >> 5] >> (i & 0x1fU) & 1U);
    }
    void __kh_set_used(T)(khint32_t* flag, T i)
    {
        (flag[i >> 5] |= 1U << (i & 0x1fU));
    }
    void __kh_set_unused(T)(khint32_t* flag, T i)
    {
        (flag[i >> 5] &= ~(1U << (i & 0x1fU)));
    }
    
    khint_t __kh_h2b(khint_t hash, khint_t bits) 
    { 
        return hash * 2654435769U >> (32 - bits); 
    }

    auto __kh_fsize(khint_t m){
        return ((m) < 32? 1 : (m)>>5);
    }
}

alias kcalloc = calloc;

alias kmalloc = malloc;

alias krealloc = realloc;

alias kfree = free;

/// Straight port of khashl's generic C approach
/// Can use cached-hashes for faster comparison of string key hashes 
template khashl(KT, VT, bool kh_is_map = true, bool cached = false, bool useGC = true)
{
    static assert(!isSigned!KT, "Numeric key types must be unsigned -- try uint instead of int, etc.");

    alias __hash_func = kh_hash!KT.kh_hash_func;
    alias __hash_equal= kh_equal!(Bucket,cached).kh_hash_equal;

    alias kh_t = khashl; /// klib uses 'kh_t' struct name

    struct Bucket {
        KT key;
        static if(kh_is_map) VT val;
        static if(cached) khint_t hash;
    }

    struct khashl        // @suppress(dscanner.style.phobos_naming_convention)
    {
        khint_t bits, count; 
		khint32_t *used; 
		Bucket * keys; 

        ~this()
        {
            //kh_destroy(&this); // the free(h) at the end of kh_destroy will SIGSEGV
            static if (useGC) {
                GC.removeRange(this.keys);
            }
            kfree(cast(void*) this.keys);
            kfree(cast(void*) this.used);
        }
        
        /// Lookup by key
        ref VT opIndex(KT key)
        {
            Bucket ins;
            ins.key = key;
            static if(cached) ins.hash = __hash_func(ins.key);
            auto x = kh_get(&this, ins);
            return this.keys[x].val;
        }

        /// Assign by key
        void opIndexAssign(VT val, KT key)
        {
            int absent;
            Bucket ins;
            ins.key = key;
            static if(cached) ins.hash = __hash_func(ins.key);
            auto x = kh_put(&this, ins, &absent);
            this.keys[x].val = val;
            static if(cached) this.keys[x].hash = ins.hash;
        }

        /// remove key/value pair
        void remove(KT key)
        {
            Bucket ins;
            ins.key = key;
            static if(cached) ins.hash = __hash_func(ins.key);
            auto x = kh_get(&this, ins);
            kh_del(&this, x);
        }

        /// Get or create if does not exist; mirror built-in hashmap
        /// https://dlang.org/spec/hash-map.html#inserting_if_not_present
        ref VT require(KT key, lazy VT initval)
        {
            static assert (kh_is_map == true, "require() not sensible in a hash set");
            Bucket ins;
            ins.key = key;
            static if(cached) ins.hash = __hash_func(ins.key);
            auto x = kh_get(&this, ins);
            if (x == kh_end(&this)) {
                // not present
                int absent;
                x = kh_put(&this, ins, &absent);
                this.keys[x].val = initval;
                static if(cached) this.keys[x].hash = ins.hash;
            }
            return this.keys[x].val;
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
                    else if (__kh_used(this.kh.used, this.itr) == 0) {
                        while(__kh_used(this.kh.used, this.itr) == 0) {
                            this.popFront();
                            if (this.itr == kh_end(this.kh)) return true;
                        }
                        return false;
                    }
                    return false;
                }
                ref KT front()
                {
                    return kh.keys[this.itr].key;
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
    khint_t kh_putp(kh_t* h, Bucket * key, int* absent);
    khint_t kh_put(kh_t* h, Bucket key, int* absent);
    int kh_del(kh_t* h, khint_t i);
  
    deprecated("kept for source-level homology; use D-style RAII")
    kh_t* kh_init()
    {
        return cast(kh_t*) kcalloc(1, kh_t.sizeof);
    }
  
    deprecated("kept for source-level homology; kfree(h) will SIGSEGV when called as kh_destroy(&this)")
    void kh_destroy(kh_t* h)
    {
        if (h)
        {
            kfree(cast(void*) h.keys);
            kfree(cast(void*) h.used);
            kfree(h);
        }
    }
  
    void kh_clear(kh_t* h)
    {
      if (h && h.used)
      {
        uint32_t n_buckets = 1U << h.bits; 
        memset(h.used, 0, __kh_fsize(n_buckets) * khint32_t.sizeof); 
        h.count = 0; 
      }
    }
  
    khint_t kh_getp(const(kh_t)* h, Bucket * key)
    {
        khint_t i, last, n_buckets, mask; 
		if (h.keys == null) return 0;
		n_buckets = 1U << h.bits;
		mask = n_buckets - 1U;

        /// if using caching, don't rehash key
        static if(cached) i = last = __kh_h2b((*key).hash, h.bits);
		else i = last = __kh_h2b(__hash_func((*key).key), h.bits);
        
		while (__kh_used(h.used, i) && !__hash_equal(h.keys[i], *key)) {
			i = (i + 1U) & mask;
			if (i == last) return n_buckets;
		}
		return !__kh_used(h.used, i)? n_buckets : i;
    }
	khint_t kh_get(const(kh_t) *h, Bucket key) { return kh_getp(h, &key); }

    int kh_resize(kh_t *h, khint_t new_n_buckets)
	{
        khint32_t * new_used = null;
		khint_t j = 0, x = new_n_buckets, n_buckets, new_bits, new_mask;
		while ((x >>= 1) != 0) ++j;
		if (new_n_buckets & (new_n_buckets - 1)) ++j;
		new_bits = j > 2? j : 2;
		new_n_buckets = 1U << new_bits;
		if (h.count > (new_n_buckets>>1) + (new_n_buckets>>2)) return 0; /* requested size is too small */
		new_used = cast(khint32_t*)kmalloc(__kh_fsize(new_n_buckets) * khint32_t.sizeof);
		memset(new_used, 0, __kh_fsize(new_n_buckets) * khint32_t.sizeof);
		if (!new_used) return -1; /* not enough memory */
		n_buckets = h.keys? 1U<<h.bits : 0U;
		if (n_buckets < new_n_buckets) { /* expand */
			Bucket *new_keys = cast(Bucket*)krealloc(cast(void*)h.keys, new_n_buckets * Bucket.sizeof);
			if (!new_keys) { kfree(new_used); return -1; }
			h.keys = new_keys;
		} /* otherwise shrink */
		new_mask = new_n_buckets - 1;
		for (j = 0; j != n_buckets; ++j) {
			Bucket key;
			if (!__kh_used(h.used, j)) continue;
			key = h.keys[j];
			__kh_set_unused(h.used, j);
			while (1) { /* kick-out process; sort of like in Cuckoo hashing */
				khint_t i;

                /// if using caching, don't rehash key
                static if(cached) i = __kh_h2b(key.hash, new_bits);
				else i = __kh_h2b(__hash_func(key.key), new_bits);

				while (__kh_used(new_used, i)) i = (i + 1) & new_mask;
				__kh_set_used(new_used, i);
				if (i < n_buckets && __kh_used(h.used, i)) { /* kick out the existing element */
					{ Bucket tmp = h.keys[i]; h.keys[i] = key; key = tmp; }
					__kh_set_unused(h.used, i); /* mark it as deleted in the old hash table */
				} else { /* write the element and jump out of the loop */
					h.keys[i] = key;
					break;
				}
			}
		}
		if (n_buckets > new_n_buckets) /* shrink the hash table */
			h.keys = cast(Bucket*)krealloc(cast(void *)h.keys, new_n_buckets * Bucket.sizeof);
		kfree(h.used); /* free the working space */
		h.used = new_used, h.bits = new_bits;
		return 0;
	}

	khint_t kh_putp(kh_t *h, Bucket * key, int *absent)
	{
		khint_t n_buckets, i, last, mask;
		n_buckets = h.keys? 1U<<h.bits : 0U;
		*absent = -1;
		if (h.count >= (n_buckets>>1) + (n_buckets>>2)) { /* rehashing */
			if (kh_resize(h, n_buckets + 1U) < 0)
				return n_buckets;
			n_buckets = 1U<<h.bits;
		} /* TODO: to implement automatically shrinking; resize() already support shrinking */
		mask = n_buckets - 1;

        /// if using caching, don't rehash key
        static if(cached) i = last = __kh_h2b((*key).hash, h.bits);
		else i = last = __kh_h2b(__hash_func((*key).key), h.bits);


		while (__kh_used(h.used, i) && !__hash_equal(h.keys[i], *key)) {
			i = (i + 1U) & mask;
			if (i == last) break;
		}
		if (!__kh_used(h.used, i)) { /* not present at all */
			h.keys[i] = *key;
			__kh_set_used(h.used, i);
			++h.count;
			*absent = 1;
		} else *absent = 0; /* Don't touch h.keys[i] if present */
		return i;
	}
    khint_t kh_put(kh_t *h, Bucket key, int *absent) { return kh_putp(h, &key, absent); }

    int kh_del(kh_t *h, khint_t i)
    {
        khint_t j = i, k, mask, n_buckets;
		if (h.keys == null) return 0;
		n_buckets = 1U<<h.bits;
		mask = n_buckets - 1U;
		while (1) {
			j = (j + 1U) & mask;
			if (j == i || !__kh_used(h.used, j)) break; /* j==i only when the table is completely full */

            /// if using caching, don't rehash key
            static if(cached) k = __kh_h2b(h.keys[j].hash, h.bits);
			else k = __kh_h2b(__hash_func(h.keys[j].key), h.bits);

			if ((j > i && (k <= i || k > j)) || (j < i && (k <= i && k > j)))
				h.keys[i] = h.keys[j], i = j;
		}
		__kh_set_unused(h.used, i);
		--h.count;
		return 1;
    }

    auto kh_bucket(const(kh_t)* h, khint_t x)
    {
        return h.keys[x];
    }

    auto kh_key(const(kh_t)* h, khint_t x)
    {
        return h.keys[x].key;
    }

    auto kh_val(const(kh_t)* h, khint_t x)
    {
        return h.keys[x].val;
    }

    auto kh_end(const(kh_t)* h)
    {
        return kh_capacity(h);
    }

    auto kh_size(const(kh_t)* h)
    {
        return h.count;
    }

    auto kh_capacity(const(kh_t)* h)
    {
        return h.keys ? 1U<<h.bits : 0U;
    }

}

/** --- BEGIN OF HASH FUNCTIONS --- */
template kh_hash(T)
{
pragma(inline, true)
{
    auto kh_hash_func(T)(T key)
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

    auto kh_hash_func(T)(T key)
    if (is(T == ulong) || is(T == uint64_t) || is(T == khint64_t))
    {
        key = ~key + (key << 21);
        key = key ^ key >> 24;
        key = (key + (key << 3)) + (key << 8);
        key = key ^ key >> 14;
        key = (key + (key << 2)) + (key << 4);
        key = key ^ key >> 28;
        key = key + (key << 31);
        return cast(khint_t) key;
    }

    khint_t kh_hash_str(const(char)* s)
    {
        khint_t h = cast(khint_t)*s;
        if (h) for  (++s; *s; ++s) h = (h << 5) - h + cast(khint_t)*s;
        return h;
    }
    
    auto kh_hash_func(T)(T* key)
    if(is(T == char) || is(T == const(char)) || is(T == immutable(char)))
    {
        return kh_hash_str(key);
    }

    auto kh_hash_func(T)(T key)
    if(isSomeString!T)
    {
        // rewrite __ac_X31_hash_string for D string/smart array
        if (key.length == 0) return 0;
        khint_t h = key[0];
        for (int i=1; i<key.length; ++i)
            h = (h << 5) - h + cast(khint_t) key[i];
        return h;
    }
    
    

} // end pragma(inline, true)
} // end template kh_hash

/// In order to take advantage of cached-hashes
/// our equality function will actually take the bucket type as opposed to just the key.
/// This allows it to access both the store hash and the key itself.
template kh_equal(T, bool cached)
{
pragma(inline,true)
{
    static assert(hasMember!(T, "key"));
    static if(cached) static assert(hasMember!(T, "hash"));

    bool kh_hash_equal(T)(T a, T b)
    if (isNumeric!(typeof(__traits(getMember,T,"key"))))
    {
        static assert (cached == false, "No reason to cache hash for integer keys");
        return (a.key == b.key);
    }
    
    bool kh_hash_equal(T)(T* a, T* b)
    if(
        is(typeof(__traits(getMember,T,"key")) == char) || 
        is(typeof(__traits(getMember,T,"key")) == const(char)) || 
        is(typeof(__traits(getMember,T,"key")) == immutable(char)))
    {
        static if(cached) return (a.hash == b.hash) && (strcmp(a, b) == 0);
        else return (strcmp(a.key, b.key) == 0);
    }

    bool kh_hash_equal(T)(T a, T b)
    if(isSomeString!(typeof(__traits(getMember,T,"key"))))
    {
        static if(cached) return (a.hash == b.hash) && (a.key == b.key);
        else return (a.key == b.key);
    }
} // end pragma(inline, true)
} // end template kh_equal
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
//#define kh_exist(h, x) (!__ac_iseither((h).flags, (x)))
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get key given an iterator
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  x     Iterator to the bucket [khint_t]
  @return       Key [type of keys]
 */
//#define kh_key(h, x) ((h).keys[x])
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get value given an iterator
  @param  h     Pointer to the hash table [khash_t(name)*]
  @param  x     Iterator to the bucket [khint_t]
  @return       Value [type of values]
  @discussion   For hash sets, calling this results in segfault.
 */
//#define kh_val(h, x) ((h).vals[x])
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Alias of kh_val()
 */
//#define kh_value(h, x) ((h).vals[x])
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
//#define kh_end(h) ((h).n_buckets)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get the number of elements in the hash table
  @param  h     Pointer to the hash table [khash_t(name)*]
  @return       Number of elements in the hash table [khint_t]
 */
//#define kh_size(h) ((h).size)
// Moved into template khash(KT, VT)

/*! @function
  @abstract     Get the number of buckets in the hash table
  @param  h     Pointer to the hash table [khash_t(name)*]
  @return       Number of buckets in the hash table [khint_t]
 */
//#define kh_n_buckets(h) ((h).n_buckets)
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

    writeln("khash unit tests");

    // test: numeric key type must be unsigned
    assert(__traits(compiles, khash!(int, int)) is false);
    assert(__traits(compiles, khash!(uint,int)) is true);

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
    assert(kh[5] == 'J');

    kh[1] = 'O';
    kh[99] = 'N';

    // test: foreach by key
    /*foreach(k; kh.byKey())
        writefln("Key: %s", k);*/
    import std.array : array;
    assert(kh.byKey().array == [5, 1, 99]);

    // test: byKey on Empty hash table
    auto kh_empty = khash!(uint, char)(); // @suppress(dscanner.suspicious.unmodified)
    assert(kh_empty.byKey.array == []);

    // test: keytype string
    auto kh_string = khash!(string, int)();
    kh_string["test"] = 5;
    assert( kh_string["test"] == 5 );

    // test: valtype string
    auto kh_valstring = khash!(uint, string)();
    kh_valstring[42] = "Adams";
    assert( kh_valstring[42] == "Adams" );

    // test: require
    const auto fw = kh_string.require("flammenwerfer", 21);
    assert(fw == 21);
}
