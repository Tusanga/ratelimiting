# ratelimiting
Rate limiting library in dlang language

## Features
  - Single leaky bucket rate limiter

  - Map of leaky bucket rate limiters all with same limits using string as key

  - Sketch of leaky bucket rate limiters all with same limits using string as key and with a constant memory footprint

  - Check for one or more counts/units at a time

## Be-aware
  - The library is as of now considered too immature to be used in production

  - RateLimiterLeakyBucketMap code can/should be optimized

  - RateLimiterLeakyBucketSketch hash functions are for now simply bit slices of same sha224 value

------------
### Single rate limiter
  Usage:

      RateLimiterLeakyBucket myRateLimiter;

      // Syntax: init(count, duration)
      // Allow 2 per 10 seconds
      myRateLimiter.init(2,10);

      // Syntax: check(timestamp, count)
      bool r = myRateLimiter.check(now(), 1);
      // check call returns true if allowed

      // Alternatively use DateTime or SysTime timestamp
      r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);

------------
### Rate limiter map
  Usage:

      RateLimiterLeakyBucketMap myRateLimiter;

      // Syntax: init(count, duration)
      // Allow 2 per 10 seconds
      myRateLimiter.init(2,10);

      // Syntax: check(key, timestamp, count)
      // Here using static "abc" string as key
      // Common choices for keys are IP addresses and usernames
      bool r = myRateLimiter.check("abc", now(), 1);
      // check call returns true if allowed

      // Alternatively use DateTime or SysTime timestamp
      r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);

      // Optionally perform garbage collection if needed
      // Be aware of run time, which may be too long for some applications
      // Syntax: performGarbageCollection(timestamp)
      myRateLimiter.performGarbageCollection(now());

  In order to remove seldom used entries the following approached is used:
  When an existing leaky bucket is empty (i.e. no action for a some time) and a check is performed with a count of exactly 1, the bucket is deleted.

------------
### Rate limiter sketch
  Internal workings are somewhat similar to count-min sketch

  Usage:

      RateLimiterLeakyBucketSketch myRateLimiter;

      // Syntax: init(count, duration, rows, columns)
      // Allow 2 per 10 seconds
      // Use sketch with 2 rows (i.e. 3 hash functions) and 5 columns (i.e. use computed hash values modulus 5)
      myRateLimiter.init(2, 10, 3, 5);

      // Syntax: check(key, timestamp, count)
      // Here using static "abc" string as key
      // Common choices for keys are IP addresses and usernames
      r = myRateLimiter.check("abc", now(), 1);
      // check call returns true if allowed

      // Alternatively use DateTime or SysTime timestamp
      r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);

