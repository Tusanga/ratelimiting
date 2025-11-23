// Ratelimiting library
// (c) Adam Williams 2025
// File: ratelimiting.d
// Implements the rate check functionality


module ratelimiting;


import std.stdio;

import std.datetime.date;
import std.datetime.systime;
import std.datetime.timezone: UTC;


unittest
{
  writeln("\n\nUNITTEST - MODULE RATELIMITING\n");
}

// ---------------------------------------------------------------------

alias TypeRcFloat         = float;

alias now                 = Clock.currTime;

// Using format 'YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ'
alias timestampFromString = SysTime.fromISOExtString;

// ---------------------------------------------------------------------
// Limits and state are separate to allow for one limits struct to be associated with many states in rate limiter maps and sketches

// Struct containing ONLY rate limiter limits but not the current state
struct LeakyBucketLimits
{
    private __gshared TypeRcFloat limitCount     = 0.0;
    private __gshared long        limitUSeconds  = 0;
    private __gshared TypeRcFloat rate;

    void init(ulong myLimitCount, ulong myLimitSeconds)
    {
      assert( myLimitCount   > 0);
      assert( myLimitSeconds > 0);

      limitCount     = cast(TypeRcFloat)myLimitCount;
      limitUSeconds  = myLimitSeconds * 1_000_000; // Using usecs
      rate           = limitCount / (1.0 * limitUSeconds);
    } // init

    string toString()
    {
      import std.format: format;
      string temp = "limitCount = %f ; limitUSeconds = %f".format(limitCount, limitUSeconds);
      return temp;
    } // toString
}


// Struct containing ONLY rate limiter current state but not the limits
struct LeakyBucketElement
{
    private TypeRcFloat           currentLevel   = 0.0;
    private SysTime               lastTimestamp  = SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC());

    string toString()
    {
      import std.format: format;
      string temp = "currentLevel = %f ; lastTimestamp = %s".format(currentLevel, lastTimestamp.toISOExtString());
      return temp;
    } // toString

    TypeRcFloat update(DateTime timestampDateTime, ref LeakyBucketLimits limits)
    {
      SysTime timestamp = SysTime(timestampDateTime, UTC());
      return update(timestamp, limits);
    } // update

    TypeRcFloat update(SysTime timestampSysTime, ref LeakyBucketLimits limits)
    {
      assert(currentLevel >= 0.0);

      //SysTime timestamp = SysTime(timestampDateTime, UTC());
      SysTime timestamp = timestampSysTime;
      assert(timestamp >= lastTimestamp);

      auto diffTimestampRaw = timestamp - lastTimestamp;    // Type Duration
      long diffTimestamp = diffTimestampRaw.total!"usecs";  // Type long

      //writeln(diffTimestamp, " ", currentLevel, " ", limits.rate, " " , limits.limitUSeconds, " " , toString()); // DEBUG

      if (diffTimestamp >= limits.limitUSeconds)
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
    bool check(TypeRcFloat count, ref LeakyBucketLimits limits)
    {
      TypeRcFloat minLevel = 0.0;
      return check(count, limits, minLevel);
    } // check

    bool check(TypeRcFloat count, ref LeakyBucketLimits limits, TypeRcFloat minLevel)
    {
      assert(currentLevel >= 0.0);
      assert(minLevel     >= 0.0);

      static import std.math;
      TypeRcFloat currentLevelMaxed = std.math.fmax(currentLevel, minLevel);
      assert(currentLevelMaxed >= 0.0);

      if (currentLevelMaxed + count > limits.limitCount)
      {
        return false;
      }

      currentLevel = currentLevelMaxed + count;
      assert(currentLevel >= 0.0);

      return true;
    } // check
} // struct LeakyBucketElement

// ---------------------------------------------------------------------

// Single rate limiter
// Contains one limits struct and one current state struct
struct RateLimiterLeakyBucket
{
  LeakyBucketLimits  limits;
  LeakyBucketElement element;

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

  bool check(DateTime timestampDateTime, TypeRcFloat count)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    return check(timestamp, count);
  } // check

  bool check(SysTime timestamp, TypeRcFloat count)
  {
    LeakyBucketElement* elementPtr = &element;
    // Ignore return value
    (*elementPtr).update(timestamp, limits);
    return (*elementPtr).check(count, limits);
  } // check
} // struct RateLimiterLeakyBucket

unittest
{
  writeln("\nUNITTEST - RateLimiterLeakyBucket\n");

  RateLimiterLeakyBucket myRateLimiter;
  myRateLimiter.init(2,10);
  writeln(myRateLimiter);

  bool r;

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 5), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  // Testing with SysTime input
  r = myRateLimiter.check(Clock.currTime(), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check(now(), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);
}

// ---------------------------------------------------------------------

// Dynamic array of rate limiters with same limits
// Contains one limits struct and many current state struct
// Each rate limiters is identified by a string key
struct RateLimiterLeakyBucketMap
{
  LeakyBucketLimits          limits;
  LeakyBucketElement[string] elements;

  void init(ulong myLimitCount, ulong myLimitSeconds)
  {
    limits.init(myLimitCount, myLimitSeconds);
  } // init

  string toString()
  {
    import std.format: format;

    string[] tempList;
    foreach(key, element; elements)
    {
      tempList ~= "('%s' ; %s)".format(key, element.toString);
    }
    static import std.array;
    string temp = "%s ; %s".format(limits.toString, std.array.join(tempList, " , "));
    return temp;
  } // toString

  bool check(string key, DateTime timestampDateTime, TypeRcFloat count)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    return check(key, timestamp, count);
  } // check

  // Not optimized for performance.
  // To-do: Look into using require/update
  bool check(string key, SysTime timestamp, TypeRcFloat count)
  {
    LeakyBucketElement* element = (key in elements);
    if (element is null)
    {
      elements[key] = LeakyBucketElement();
      element = (key in elements);
      (*element).update(timestamp, limits);

      auto checkResult = (*element).check(count, limits);

      return checkResult;
    }
    else
    {
      auto currentLevel = (*element).update(timestamp, limits);

      // Do not add count when count is one, element is aready present in map and element has a currentLevel of zero.
      // This works as a kind of garbage collector for the map
      if ((currentLevel == 0.0) && (count == 1.0))
      {
        elements.remove(key);
        return true;
      }

      auto checkResult = (*element).check(count, limits);
      return checkResult;
    }
  } // check

  void performGarbageCollection(DateTime timestampDateTime)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    performGarbageCollection(timestamp);
  } // performGarbageCollection

  void performGarbageCollection(SysTime timestamp)
  {
    string[] keysToBeDeleted;
    foreach (string key, ref LeakyBucketElement element; elements)
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

} // struct RateLimiterLeakyBucketMap


unittest
{
  writeln("\nUNITTEST - RateLimiterLeakyBucketMap\n");

  RateLimiterLeakyBucketMap myRateLimiter;
  myRateLimiter.init(2,10);
  writeln(myRateLimiter);

  writeln("Garbage collection");
  myRateLimiter.performGarbageCollection(DateTime(2020, 1, 1, 0, 1, 0));
  writeln(myRateLimiter);

  bool r;

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 1), 2);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 2), 2);
  writeln(r);
  writeln(myRateLimiter);
  assert(!r);

  writeln("Garbage collection");
  myRateLimiter.performGarbageCollection(DateTime(2020, 1, 1, 0, 2, 0));
  writeln(myRateLimiter);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 5), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 12), 2);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  writeln("Garbage collection");
  myRateLimiter.performGarbageCollection(DateTime(2020, 1, 1, 0, 1, 0));
  writeln(myRateLimiter);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 1, 0), 1);
  assert(r);
  writeln(r);
  writeln(myRateLimiter);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 2, 0), 1.5);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  // Testing with SysTime input
  r = myRateLimiter.check("abc", Clock.currTime(), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", now(), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);
}

//// ---------------------------------------------------------------------
//// ---------------------------------------------------------------------

void calculateHashValues(ref string key, ref uint[] hashList, ubyte rowCount)
{
  assert(rowCount == hashList.length);

  static import std.digest.sha;
  ubyte[28] hashUbyte = std.digest.sha.sha224Of(key);
  uint[]    hashUint  = cast(uint[]) hashUbyte;
  assert(4 * hashUint.length == hashUbyte.length);
  assert(hashUbyte.length <= 28);

  for (ubyte row = 0; row < rowCount; row++)
  {
    hashList[row] = hashUint [row];
  }
} // calculateHashValues

//// ---------------------------------------------------------------------

// Sketch used for potentially infinite number of rate limiters all with same limits
// Similarities with count–min sketch probalistic data structure
// The number of hash functions used is called row. The different hash values identify the columns.
// Each rate limiters is identified by a string key

struct RateLimiterLeakyBucketSketch
{
  LeakyBucketLimits     limits;
  LeakyBucketElement[]  elements;
  ubyte                 rowCount = 0;
  uint                  colCount = 0;
  uint[]                hashArray;
  bool                  hasBeenInitialized = false;

  void init(ulong myLimitCount, ulong myLimitSeconds, ubyte myRowCount, uint myColCount)
  {
    assert(!hasBeenInitialized);

    limits.init(myLimitCount, myLimitSeconds);
    assert(myRowCount >= 1);
    assert(myRowCount <= 7);
    rowCount = myRowCount;
    colCount = myColCount;
    elements = new LeakyBucketElement[](rowCount * colCount);

    hashArray = new uint[](rowCount);

    hasBeenInitialized = true;
  } // init

  string toString()
  {
    assert(hasBeenInitialized);

    import std.format: format;

    string[] tempList;
    foreach(element; elements)
    {
      tempList ~= "(%s)".format(element.toString);
    }
    static import std.array;
    string temp = "%s ;\n%s".format(limits.toString, std.array.join(tempList, " ,\n"));
    return temp;
  } // toString

  bool check(string key, DateTime timestampDateTime, TypeRcFloat count)
  {
    SysTime timestamp = SysTime(timestampDateTime, UTC());
    return check(key, timestamp, count);
  } // check

  bool check(string key, SysTime timestamp, TypeRcFloat count)
  {
    assert(hasBeenInitialized);

    assert(rowCount <= hashArray.length);
    calculateHashValues(key, hashArray, rowCount);

    TypeRcFloat minCurrentLevel = TypeRcFloat.max;
    for (ubyte row = 0; row < rowCount; row++)
    {
      auto hashValue = hashArray[row];
      uint col = hashValue % colCount;
      assert(col >= 0);
      assert(col < colCount);
      LeakyBucketElement* element = &(elements[row * colCount + col]);
      auto currentLevel = (*element).update(timestamp, limits);
      static import std.math;
      minCurrentLevel = std.math.fmin(minCurrentLevel, currentLevel);
    }

    assert(minCurrentLevel >= 0.0);

    if (minCurrentLevel + count > limits.limitCount)
    {
      return false;
    }

    bool combinedCheckResult = true;
    for (ubyte row = 0; row < rowCount; row++)
    {
      uint col = hashArray[row] % colCount;
      assert(col < colCount);
      LeakyBucketElement* element = &(elements[row * colCount + col]);
      bool checkResult = (*element).check(count, limits, minCurrentLevel);
      combinedCheckResult = combinedCheckResult & checkResult;
    }

    return true;
  } // check

} // struct RateLimiterLeakyBucketSketch

unittest
{
  writeln("\nUNITTEST - RateLimiterLeakyBucketSketch\n");

  RateLimiterLeakyBucketSketch myRateLimiter;
  myRateLimiter.init(2, 10, 2, 5);
  writeln(myRateLimiter);

  bool r;

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 1), 2);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 2), 2);
  writeln(r);
  writeln(myRateLimiter);
  assert(!r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 0, 5), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", DateTime(2020, 1, 1, 0, 0, 12), 2);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 1, 0), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("abc", DateTime(2020, 1, 1, 0, 2, 0), 1.5);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  // Testing with SysTime input
  r = myRateLimiter.check("abc", Clock.currTime(), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);

  r = myRateLimiter.check("def", now(), 1);
  writeln(r);
  writeln(myRateLimiter);
  assert(r);
}

unittest
{
  // Run many random checks on rate limiter sketch with different keys, timestamps and counts

  writeln("\nUNITTEST - RateLimiterLeakyBucketSketch #2\n");

  import std.random: MinstdRand, randomShuffle;
  auto rnd = MinstdRand(42);

  uint countFalse = 0;
  uint countTrue  = 0;

  RateLimiterLeakyBucketSketch myRateLimiter;
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

  writeln("True = ", countTrue, " ; False = ", countFalse);
}

unittest
{
  writeln("\nUNITTEST - Alias functions\n");

  SysTime n = now();
  writefln("now: %s", n.toISOExtString);

  SysTime ts = timestampFromString("2025-01-12T13:14:15.123");
  writefln("timestamp: %s", ts.toISOExtString);
}

//// ---------------------------------------------------------------------

unittest
{
  writeln("\nUNITTEST - MODULE RATELIMITING - DONE\n");
}

//// ---------------------------------------------------------------------
