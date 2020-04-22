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

int main()
{
    writeln("hashmap benchmarks");

    enum NUMBER_OF_ITEMS = 500_000;

    void testContainerInsert(alias Container, string ContainerName, bool cached = false)()
    {
        static if(cached){
            static assert(ContainerName == "khashl (cached)");
            auto c = Container!(string, int,true,true,true)();
        }else{
            auto c = Container!(string, int)();
        }

        StopWatch sw = StopWatch(AutoStart.yes);
        foreach (i; 0 .. NUMBER_OF_ITEMS)
            //c.insert(i);
            c[randomUUID().toString] = i;
        sw.stop();
        writeln("Inserts for ", ContainerName, " finished in ",
            sw.peek.total!"msecs", " milliseconds.");
    }

    void testContainerLookup(alias Container, string ContainerName)()
    {
        import std.random : uniform;

        auto c = Container!(uint, string)();
        // untimed insert
        foreach (i; 0 .. NUMBER_OF_ITEMS)
            c[i] = randomUUID().toString;
        StopWatch sw = StopWatch(AutoStart.yes);
        // serial lookups
        foreach (i; 0 .. NUMBER_OF_ITEMS)
            global_x = c[i];
        sw.stop();
        writeln("Serial Lookups for ", ContainerName, " finished in ",
            sw.peek.total!"msecs", " milliseconds.");
        
        sw.reset();

        // random lookups
        sw.start();
        foreach(i; 0 .. NUMBER_OF_ITEMS)
            global_x = c[ uniform(0, NUMBER_OF_ITEMS) ];
        sw.stop();
        writeln("Random lookups for ", ContainerName, " finished in ",
            sw.peek.total!"msecs", " milliseconds.");
        
        writeln("Confirming stored value of last lookup: ", global_x);
    }

    testContainerInsert!(HashMap, "HashMap");
    testContainerInsert!(khash, "khash");
    testContainerInsert!(khashl, "khashl");
    testContainerInsert!(khashl, "khashl (cached)",true);

    testContainerLookup!(HashMap, "HashMap");
    testContainerLookup!(khash, "khash");
    testContainerLookup!(khashl, "khashl");

    return 0;
}
