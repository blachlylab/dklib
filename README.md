Library of efficient algorithms and data structures ported to templatized D
from attractivechaos' generic C approach: https://github.com/attractivechaos/klib

# khash

## Fast

Comparison with emsi_containers HashMap:

Time, in msec, for n=500,000 operations benchmarked on linux VM; ldc2 -release

Operation | HashMap | khash
----------+---------+------
Insert    | 3573    | 2347
Lookup (Serial)|145 | 26
Lookup (Random)|282 | 84

## Notes
Key type may be numeric, C style string, D style string.
If numeric, must be unsigned

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