/+dub.sdl:
dependency "emsi_containers" version="~>0.7"
dependency "dklib" path="../.."
+/
import dklib.khash;
import dklib.khashl;
import containers;

import std.datetime.stopwatch : StopWatch, AutoStart;
import std.stdio;
import std.uuid : randomUUID;

string global_x; /// for benchmarking to prevent elision(?)
uint global_y;

int main()
{
    writeln("hashmap benchmarks");

    enum NUMBER_OF_ITEMS = 500_000;

    void testContainerInsert(T, alias Container, string ContainerName, bool cached = false)()
    if(is(T == uint) || is(T == string))
    {
        static if(cached){
            static assert(ContainerName == "khashl (cached)");
            static if(is(T == uint)) auto c = Container!(uint, string,true,true,true)();
            else auto c = Container!(string, uint,true,true,true)();
        }else{
            static if(is(T == uint)) auto c = Container!(uint, string)();
            else auto c = Container!(string, uint)();
        }

        StopWatch sw = StopWatch(AutoStart.yes);
        foreach (i; 0 .. NUMBER_OF_ITEMS)
            //c.insert(i);
            static if(is(T == uint)) c[i] = randomUUID().toString;
            else c[randomUUID().toString] = i;
        sw.stop();
        writeln(T.stringof~" inserts for ", ContainerName, " finished in ",
            sw.peek.total!"msecs", " milliseconds.");
    }

    void testContainerLookup(T, alias Container, string ContainerName, bool cached = false)()
    if(is(T == uint) || is(T == string))
    {
        import std.random : uniform;

        static if(cached){
            static assert(ContainerName == "khashl (cached)");
            static if(is(T == uint)) auto c = Container!(uint, string,true,true,true)();
            else auto c = Container!(string, uint,true,true,true)();
        }else{
            static if(is(T == uint)) auto c = Container!(uint, string)();
            else auto c = Container!(string, uint)();
        }
        // untimed insert
        string[] items = new string[NUMBER_OF_ITEMS];
        foreach (i; 0 .. NUMBER_OF_ITEMS)
            items[i] = randomUUID().toString;
        foreach (uint i,item; items)
            static if(is(T == uint)) c[i] = item;
            else c[item] = i;
        StopWatch sw = StopWatch(AutoStart.yes);
        // serial lookups
        foreach (i; 0 .. NUMBER_OF_ITEMS)
            static if(is(T == uint)) global_x = c[i];
            else global_y = c[items[i]];
        sw.stop();
        writeln("Serial "~T.stringof~" lookups for ", ContainerName, " finished in ",
            sw.peek.total!"msecs", " milliseconds.");
        
        sw.reset();

        // random lookups
        sw.start();
        foreach(i; 0 .. NUMBER_OF_ITEMS)
            static if(is(T == uint)) global_x = c[ uniform(0, NUMBER_OF_ITEMS) ];
            else global_y = c[ items[uniform(0, NUMBER_OF_ITEMS)] ];
        sw.stop();
        writeln("Random "~ T.stringof ~" lookups for ", ContainerName, " finished in ",
            sw.peek.total!"msecs", " milliseconds.");
        
        writeln("Confirming stored value of last lookup: ", global_x);
    }

    testContainerInsert!(uint, HashMap, "HashMap");
    testContainerInsert!(uint, khash, "khash");
    testContainerInsert!(uint, khashl, "khashl");
    // testContainerInsert!(uint, khashl, "khashl (cached)",true);

    testContainerInsert!(string, HashMap, "HashMap");
    testContainerInsert!(string, khash, "khash");
    testContainerInsert!(string, khashl, "khashl");
    testContainerInsert!(string, khashl, "khashl (cached)",true);

    testContainerLookup!(uint, HashMap, "HashMap");
    testContainerLookup!(uint, khash, "khash");
    testContainerLookup!(uint, khashl, "khashl");
    // testContainerLookup!(uint, khashl, "khashl (cached)",true);

    testContainerLookup!(string, HashMap, "HashMap");
    testContainerLookup!(string, khash, "khash");
    testContainerLookup!(string, khashl, "khashl");
    testContainerLookup!(string, khashl, "khashl (cached)",true);

    return 0;
}
