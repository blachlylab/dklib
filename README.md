Library of efficient algorithms and data structures ported to templatized D
from attractivechaos' generic C approach: https://github.com/attractivechaos/klib

# khash & khashl

## Fast

Comparison with [emsi containers](https://github.com/dlang-community/containers) HashMap:

Time, in msec, for n=500,000 operations with uint keys benchmarked on WSL; ldc2 -release

| Operation         | HashMap | khash | khashl |
|-------------------|---------|-------|--------|
| Insert            | 1168    | 411   | 401    |
| Retrieve (Serial) | 83      | 20    | 110    |
| Retrieve (Random) | 198     | 91    | 134    |

Time, in msec, for n=500,000 operations with string keys benchmarked on WSL; ldc2 -release

| Operation         | HashMap | khash | khashl | khashl (cached) |
|-------------------|---------|-------|--------|-----------------|
| Insert            | 1727    | 782   | 903    | 494             |
| Retrieve (Serial) | 232     | 261   | 267    | 240             |
| Retrieve (Random) | 404     | 420   | 422    | 422             |


## Notes
Key type may be numeric, C style string, D style string.
If numeric, must be unsigned.

May be used as a hash map (default) or a hash set. To use as a hash set,
pass optional third template parameter `kh_is_map = false`.

By default, memory allocated by the hashmap will be scanned by the GC.
(pass optional fourth template parameter `useGC = false` to disable)

For ```khashl```, hash caching can be enabled by passing an optional fourth
 template parameter `cached = true`. This allows faster insertions for 
 string keys.

Can undergo static initialization (e.g. define as struct member
with no extra init code needed in struct ctor), unlike
[emsi containers](https://github.com/dlang-community/containers) HashMap.


## API

### Declaration
```D
auto map = khash!(keytype, valuetype);
auto map2 = khashl!(keytype, valuetype);
auto map3 = khashl!(string, valuetype,true,true); // for hash-caching with strings
```

### Assignment / Insert
```D
map["monty"] = "python";
```

### Retrieval
```D
auto val = map[key];
``` 

### Retrieve or Create
```D
auto val = map.require("fruit", "apple");
```

### Iteration
```D
foreach(x; map.byKey) {
...
}
```

## Examples

### uint -> char ; byKey
```
auto kh = khash!(uint, char)();
kh[5] = 'J';
assert(kh[5] == 'J');

kh[1] = 'O';
kh[99] = 'N';

// test: foreach by key
import std.array : array;
assert(kh.byKey().array == [5, 1, 99]);
```

### string -> int
```
auto kh_string = khash!(string, int)();
kh_string["test"] = 5;
assert( kh_string["test"] == 5 );
```

### uint -> string
```
auto kh_valstring = khash!(uint, string)();
kh_valstring[42] = "Adams";
assert( kh_valstring[42] == "Adams" );
```

### require (mimicing D builtin associative array)
```
const auto fw = kh_string.require("flammenwerfer", 21);
assert(fw == 21);
```

## BUGS

Please let me know what you find.
There may be a double free bug when making a hashmap of hashmaps.

