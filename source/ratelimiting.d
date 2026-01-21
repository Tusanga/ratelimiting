// Ratelimiting library
// (c) Adam Williams 2025-2026
// File: ratelimiting.d
// Implements the rate check functionality

module ratelimiting;

import std.datetime.date: DateTime;
import std.datetime.systime: SysTime, Clock;
import std.datetime.timezone: UTC;

unittest
{
  import std.stdio;
  writeln("UNITTEST - MODULE RATELIMITING");
}

// ---------------------------------------------------------------------

alias RLFloat             = float;
alias now                 = Clock.currTime;

// Using format 'YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ'
alias timestampFromString = SysTime.fromISOExtString;

// ---------------------------------------------------------------------
// Limits and state are separate
// This allows for one limits struct to be associated with many states
// It is used is rate limiter maps and sketches

// Struct containing ONLY rate limiter limits but not current state
struct BucketLimits
{
    private __gshared RLFloat count     = 0.0;
    private __gshared long    uSeconds  = 0;
    private __gshared RLFloat rate;

    void init(ulong myCount, ulong mySeconds)
    {
      assert(myCount   > 0);
      assert(mySeconds > 0);

      count     = cast(RLFloat)myCount;
      uSeconds  = mySeconds * 1_000_000; // Using usecs
      rate      = count / (1.0 * uSeconds);
    } // init

    string toString()
    {
      import std.format: format;
      string temp = "count = %f ; uSeconds = %f".format(count, uSeconds);
      return temp;
    } // toString
}

unittest
{
  import std.stdio;
  writeln("UNITTEST - BucketLimits");

  BucketLimits myLimits;
  myLimits.init(1,1);
  //writeln(myLimits.toString());
  assert(myLimits.toString() == "count = 1.000000 ; uSeconds = 1000000");
}

// ---------------------------------------------------------------------

// Struct containing ONLY rate limiter current state but not limits
struct BucketElement
{
    private RLFloat currentLevel   = 0.0;
    private SysTime lastTimestamp  = SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC());

    string toString()
    {
      import std.format: format;
      string temp = "currentLevel = %f ; lastTimestamp = %s".format(currentLevel, lastTimestamp.toUTC().toISOExtString());
      return temp;
    } // toString

    // Returns new current level
    RLFloat update(DateTime timestampDateTime, ref BucketLimits limits)
    {
      SysTime timestamp = SysTime(timestampDateTime, UTC());
      return update(timestamp, limits);
    } // update

    RLFloat update(SysTime timestampSysTime, ref BucketLimits limits)
    {
      assert(currentLevel >= 0.0);

      SysTime timestamp = timestampSysTime;
      assert(timestamp >= lastTimestamp);

      auto diffTimestampRaw = timestamp - lastTimestamp;    // Type Duration
      long diffTimestamp = diffTimestampRaw.total!"usecs";  // Type long

      if (diffTimestamp >= limits.uSeconds)
      {
        currentLevel = 0.0;
      }
      else if (diffTimestamp != 0)
      {
        currentLevel = currentLevel - limits.rate * diffTimestamp;
        if (currentLevel < 0.0)
        {
          currentLevel = 0.0;
        }
      }

      assert(currentLevel >= 0.0);

      lastTimestamp = timestamp;

      return currentLevel;
    } // update

    // Returns false if ratelimiter is over allowed limit
    // I.e. if current level + new count is greater than limit count
    bool check(RLFloat count, ref BucketLimits limits)
    {
      RLFloat minLevel = 0.0;
      return check(count, limits, minLevel);
    } // check

    bool check(RLFloat count, ref BucketLimits limits, RLFloat minLevel)
    {
      assert(currentLevel >= 0.0);
      assert(minLevel     >= 0.0);

      static import std.math;
      RLFloat currentLevelMaxed = std.math.fmax(currentLevel, minLevel);
      assert(currentLevelMaxed >= 0.0);

      if (currentLevelMaxed + count > limits.count)
      {
        return false;
      }

      currentLevel = currentLevelMaxed + count;
      assert(currentLevel >= 0.0);

      return true;
    } // check
} // struct BucketElement

unittest
{
  import std.stdio;
  writeln("UNITTEST - BucketElement");

  BucketElement myElement;
  //writeln(myElement.toString());
  assert(myElement.toString() == "currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z");
}

// ---------------------------------------------------------------------

// Single rate limiter
// Contains one limits struct and one elements struct with current state
struct RateLimiterBucket
{
  BucketLimits  limits;
  BucketElement element;

  void init(ulong myLimitCount, ulong myLimitSeconds)
  {
    limits.init(myLimitCount, myLimitSeconds);
  } // init

  string toString()
  {
    import std.format: format;
    string temp = "%s ; %s".format(limits.toString, element.toString);
    return temp;
  } // toString

  // Returns false if ratelimiter is overs allowed limit
  bool check(DateTime timestampDateTime, RLFloat count = 1)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    return check(timestamp, count);
  } // check

  bool check(SysTime timestamp, RLFloat count = 1)
  {
    BucketElement* elementPtr = &element;
    // Ignore return value
    (*elementPtr).update(timestamp, limits);
    return (*elementPtr).check(count, limits);
  } // check
} // struct RateLimiterBucket

unittest
{
  import std.stdio;
  writeln("UNITTEST - RateLimiterBucket #1");

  RateLimiterBucket myRateLimiter;
  myRateLimiter.init(2,10);
  //writeln(myRateLimiter.toString());
  assert(myRateLimiter.toString() == "count = 2.000000 ; uSeconds = 10000000 ; currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z");

  myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter.toString());
  assert(myRateLimiter.toString() == "count = 2.000000 ; uSeconds = 10000000 ; currentLevel = 1.000000 ; lastTimestamp = 2020-01-01T00:00:00Z");

  // Using default value (1) for count/units
  myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0));
  //writeln(myRateLimiter.toString());
  assert(myRateLimiter.toString() == "count = 2.000000 ; uSeconds = 10000000 ; currentLevel = 2.000000 ; lastTimestamp = 2020-01-01T00:00:00Z");
}

unittest
{
  import std.stdio;
  writeln("UNITTEST - RateLimiterBucket #2");

  RateLimiterBucket myRateLimiter;
  myRateLimiter.init(2,10);
  //writeln(myRateLimiter);

  bool r;

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 5), 1);
  //writeln(myRateLimiter);
  assert(r);

  // Testing with SysTime input
  r = myRateLimiter.check(Clock.currTime(), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check(now(), 1);
  //writeln(myRateLimiter);
  assert(r);
}

// ---------------------------------------------------------------------

// Dynamic array of rate limiters with same limits
// Contains one limits struct and many element structs with current state
// Each rate limiters is identified by a string key
struct RateLimiterBucketMap
{
  BucketLimits          limits;
  BucketElement[string] elements;

  void init(ulong myLimitCount, ulong myLimitSeconds)
  {
    limits.init(myLimitCount, myLimitSeconds);
  } // init

  string toString()
  {
    import std.outbuffer;
    import std.format: format;

    OutBuffer buf = new OutBuffer();

    buf.put(limits.toString);
    buf.put(" ;\n");

    ulong counter = 0;
    foreach(key, element; elements)
    {
      if (counter > 0) buf.put(" ,\n");
      counter++;
      buf.writef("('%s' ; %s)", key, element.toString);
    }
    return buf.toString();
  } // toString

  // Returns false if ratelimiter is over allowed limit
  bool check(string key, DateTime timestampDateTime, RLFloat count = 1)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    return check(key, timestamp, count);
  } // check

  bool check(string key, SysTime timestamp, RLFloat count = 1)
  {
    BucketElement* element = (key in elements);
    if (element is null)
    {
      elements[key] = BucketElement();
      element = (key in elements);
      (*element).update(timestamp, limits);

      auto checkResult = (*element).check(count, limits);

      return checkResult;
    }
    else
    {
      auto currentLevel = (*element).update(timestamp, limits);

      // Do not add count when element is aready present in map, count is one and element has a currentLevel of zero.
      // This helps reduce the number of infrequently used elements in map
      if ((currentLevel == 0.0) && (count == 1.0))
      {
        elements.remove(key);
        return true;
      }

      auto checkResult = (*element).check(count, limits);
      return checkResult;
    }
  } // check

  // Potentially a long-running function akin to stop-the-world GC
  void performGarbageCollection(DateTime timestampDateTime)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    performGarbageCollection(timestamp);
  } // performGarbageCollection

  void performGarbageCollection(SysTime timestamp)
  {
    // To-do: Look into whether this way of deleting elements can be optimized
    string[] keysToBeDeleted;

    foreach (string key, ref BucketElement element; elements)
    {
      auto currentLevel = element.update(timestamp, limits);
      if (currentLevel == 0.0)
      {
        keysToBeDeleted ~= key;
      }
    } // foreach

    foreach (key; keysToBeDeleted)
    {
      elements.remove(key);
    } // foreach
  } // performGarbageCollection

} // struct RateLimiterBucketMap

unittest
{
  import std.stdio;
  import std.string: splitLines;
  writeln("UNITTEST - RateLimiterBucketMap #1");

  RateLimiterBucketMap myRateLimiter;
  myRateLimiter.init(2,10);
  //writeln(myRateLimiter.toString().splitLines());
  assert(myRateLimiter.toString().splitLines() == ["count = 2.000000 ; uSeconds = 10000000 ;"]);

  myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter.toString().splitLines());
  assert(myRateLimiter.toString().splitLines() == ["count = 2.000000 ; uSeconds = 10000000 ;", "('abc' ; currentLevel = 1.000000 ; lastTimestamp = 2020-01-01T00:00:00Z)"]);

  // Using default value (1) for count/units
  myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0));
  //writeln(myRateLimiter.toString().splitLines());
  assert(myRateLimiter.toString().splitLines() == ["count = 2.000000 ; uSeconds = 10000000 ;", "('abc' ; currentLevel = 2.000000 ; lastTimestamp = 2020-01-01T00:00:00Z)"]);
}

unittest
{
  import std.stdio;
  writeln("UNITTEST - RateLimiterBucketMap #2");

  RateLimiterBucketMap myRateLimiter;
  myRateLimiter.init(2,10);
  //writeln(myRateLimiter);

  //writeln("Garbage collection");
  myRateLimiter.performGarbageCollection(DateTime(2020, 1, 1, 0, 1, 0));
  //writeln(myRateLimiter);

  bool r;

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 1), 2);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 2), 2);
  //writeln(myRateLimiter);
  assert(!r);

  //writeln("Garbage collection");
  myRateLimiter.performGarbageCollection(DateTime(2020, 1, 1, 0, 2, 0));
  //writeln(myRateLimiter);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 5), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 12), 2);
  //writeln(myRateLimiter);
  assert(r);

  //writeln("Garbage collection");
  myRateLimiter.performGarbageCollection(DateTime(2020, 1, 1, 0, 1, 0));
  //writeln(myRateLimiter);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 1, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 2, 0), 1.5);
  //writeln(myRateLimiter);
  assert(r);

  // Testing with SysTime input
  r = myRateLimiter.check("abc", Clock.currTime(), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", now(), 1);
  //writeln(myRateLimiter);
  assert(r);
}

// ---------------------------------------------------------------------
// ---------------------------------------------------------------------

// Each hash value in hashList is 32 bits
// Murmurhash3 outputs 128 bits
// RipeMd160   outputs 160 bits
// (128+160) / 32 = 9
immutable maxNoOfHashValues = 9;

// Uses murmurhash3 for the first four hash values due to speed.
// Uses ripemd160 for the next five hash values only if these are needed.
void calculateHashValues(ref string key, ref uint[] hashList, ubyte rowCount)
{
  assert(rowCount == hashList.length);

  assert(rowCount >= 1);
  assert(rowCount <= maxNoOfHashValues);

  import std.digest.murmurhash: digest, MurmurHash3;
  static import std.digest.ripemd;
  uint[4+5] hashUInt;
  hashUInt[0..4] = cast(uint[4])digest!(MurmurHash3!(128,64))(key);
  if (rowCount > 4)
  {
    hashUInt[4..9] = cast(uint[5])std.digest.ripemd.ripemd160Of(key);
  }

  for (ubyte row = 0; row < rowCount; row++)
  {
    hashList[row] = hashUInt[row];
  }
} // calculateHashValues

// ---------------------------------------------------------------------

// Sketch is useful for handling a very large number of keys.
// There are similarities between the internal structure and what is
// found in the count–min sketch probabilistic data structure.
// The number of hash functions used is called rowCount.
// The hash values identify the relevant columns.
// Being probabilistic there is a risk of false positives, i.e. getting
// flagged as 'over the limit' when this is not the case.
// Each rate limiters is identified by a string key.
// All elements share the same limits.

struct RateLimiterBucketSketch
{
  BucketLimits      limits;
  BucketElement[]   elements;
  ubyte             rowCount = 0;
  uint              colCount = 0;
  uint[]            hashArray;
  bool              hasBeenInitialized = false;

  void init(ulong myLimitCount, ulong myLimitSeconds, ubyte myRowCount, uint myColCount)
  {
    assert(!hasBeenInitialized);

    limits.init(myLimitCount, myLimitSeconds);
    assert(myRowCount >= 1);
    assert(myRowCount <= maxNoOfHashValues);
    rowCount = myRowCount;
    colCount = myColCount;
    elements = new BucketElement[](rowCount * colCount);

    hashArray = new uint[](rowCount);

    hasBeenInitialized = true;
  } // init

  string toString()
  {
    assert(hasBeenInitialized);

    import std.outbuffer;
    import std.format: format;

    OutBuffer buf = new OutBuffer();

    buf.put(limits.toString);
    buf.put(" ;\n");

    ulong counter = 0;
    foreach(element; elements)
    {
      if (counter > 0) buf.put(" ,\n");
      counter++;
      buf.writef("(%s)", element.toString);
    }
    return buf.toString();
  } // toString

  // Returns false if ratelimiter is over allowed limit
  bool check(string key, DateTime timestampDateTime, RLFloat count = 1)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    return check(key, timestamp, count);
  } // check

  bool check(string key, SysTime timestamp, RLFloat count = 1)
  {
    assert(hasBeenInitialized);

    assert(rowCount <= hashArray.length);
    calculateHashValues(key, hashArray, rowCount);

    RLFloat minCurrentLevel = RLFloat.max;
    for (ubyte row = 0; row < rowCount; row++)
    {
      auto hashValue = hashArray[row];
      uint col = hashValue % colCount;
      assert(col >= 0);
      assert(col < colCount);
      BucketElement* element = &(elements[row * colCount + col]);
      auto currentLevel = (*element).update(timestamp, limits);
      static import std.math;
      minCurrentLevel = std.math.fmin(minCurrentLevel, currentLevel);
    }

    assert(minCurrentLevel >= 0.0);

    if (minCurrentLevel + count > limits.count)
    {
      return false;
    }

    bool combinedCheckResult = true;
    for (ubyte row = 0; row < rowCount; row++)
    {
      uint col = hashArray[row] % colCount;
      assert(col < colCount);
      BucketElement* element = &(elements[row * colCount + col]);
      bool checkResult = (*element).check(count, limits, minCurrentLevel);
      combinedCheckResult = combinedCheckResult & checkResult;
    }

    return true;
  } // check

} // struct RateLimiterBucketSketch

unittest
{
  import std.stdio;
  import std.string: splitLines;
  writeln("UNITTEST - RateLimiterBucketSketch #1");

  RateLimiterBucketSketch myRateLimiter;
  myRateLimiter.init(2, 10, 2, 3);
  //writeln(myRateLimiter.toString().splitLines());
  assert(myRateLimiter.toString().splitLines() == ["count = 2.000000 ; uSeconds = 10000000 ;", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z)"]);

  myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter.toString().splitLines());
  //assert(myRateLimiter.toString().splitLines() == ["count = 2.000000 ; uSeconds = 10000000 ;", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 1.000000 ; lastTimestamp = 2020-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 1.000000 ; lastTimestamp = 2020-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z)"]);
  assert(myRateLimiter.toString().splitLines() == ["count = 2.000000 ; uSeconds = 10000000 ;", "(currentLevel = 1.000000 ; lastTimestamp = 2020-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 1.000000 ; lastTimestamp = 2020-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z) ,", "(currentLevel = 0.000000 ; lastTimestamp = 1970-01-01T00:00:00Z)"]);

  // Using default value (1) for count/units
  myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0));
}

unittest
{
  import std.stdio;
  writeln("UNITTEST - RateLimiterBucketSketch #2");

  RateLimiterBucketSketch myRateLimiter;
  myRateLimiter.init(2, 10, 2, 5);
  //writeln(myRateLimiter);

  bool r;

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  //writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 1), 2);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 2), 2);
  //writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 5), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 12), 2);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 1, 0), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 2, 0), 1.5);
  //writeln(myRateLimiter);
  assert(r);

  // Testing with SysTime input
  r = myRateLimiter.check("abc", Clock.currTime(), 1);
  //writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", now(), 1);
  //writeln(myRateLimiter);
  assert(r);
}

unittest
{
  // Run many random checks on rate limiter sketch with different keys, timestamps and counts

  import std.stdio;
  writeln("UNITTEST - RateLimiterBucketSketch #3");

  import std.random: MinstdRand, randomShuffle;
  auto rnd = MinstdRand(42);

  uint countFalse = 0;
  uint countTrue  = 0;

  RateLimiterBucketSketch myRateLimiter;
  myRateLimiter.init(4, 10, 5, 25);

  ubyte[] baseString = (cast(ubyte[])"abcde").dup;

  auto noOfIterations = 60*60*24;
  // Using iteration counter i as number of seconds
  for (uint i = 0; i < noOfIterations; i++)
  {
    auto hours   = i / 3600;
    auto minutes = (i % 3600) / 60;
    auto seconds = i % 60;

    // count changes between 1, 2 and 3
    auto count = 1 + (i % 3);

    // Generate new random key for every iteration to exercise hash function and so use different columns in elements array
    // Number of different random keys is limited by the length of the baseString.
    ubyte[] id = baseString.randomShuffle(rnd);

    bool checkResult = myRateLimiter.check(cast(string)id, DateTime(2020, 1, 1, hours, minutes, seconds), count);
    if (checkResult)
    { countTrue++; }
    else
    { countFalse++; }
  } // for

  //writeln("True = ", countTrue, " ; False = ", countFalse);
}

unittest
{
  import std.stdio;
  writeln("UNITTEST - Alias functions");

  SysTime n = now();
  //writefln("now: %s", n.toISOExtString);

  SysTime ts = timestampFromString("2025-01-12T13:14:15.123");
  //writefln("timestamp: %s", ts.toISOExtString);
  assert(ts.toISOExtString == "2025-01-12T13:14:15.123");
}

// ---------------------------------------------------------------------

unittest
{
  import std.stdio;
  writeln("UNITTEST - MODULE RATELIMITING - DONE");
}

// ---------------------------------------------------------------------
