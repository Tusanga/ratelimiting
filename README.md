# ratelimiting
Rate limiting library in dlang language

## Features
  - Single bucket rate limiter.

  - Map of bucket rate limiters all with same limits using string as key.

  - Sketch of bucket rate limiters all with same limits using string as key and with a constant memory footprint.

  - With sketch being probabilistic there is a risk of false positives, i.e. getting flagged as 'over limit' when this is not the case.

  - Supports check for one or more units at a time.
  
  - Limits are defined as 'units' per 'seconds'. Example: 10 units per 60 seconds.
  
  - Bursts up to 'units' are allowed. 10 units per 60 seconds and 20 units per 120 seconds will have the same average rate but diffent burst sizes of respectively 10 and 20.

## Be-aware
  - The library is as of now considered too immature to be used in production.

  - The library does not support partial checks, i.e. when a part (e.g. 2) units out of all (e.g. 5) units should be allowed.

  - RateLimiterBucketSketch can not be resized.

  - Guidelines for choosing row count and column count in RateLimiterBucketSketch are not included. Please refer to calculations for bloom filters and count-min sketches for this.

------------
### Single rate limiter
  Usage:

      RateLimiterBucket myRateLimiter;

      // Syntax: init(count, duration)
      // Allow 2 units per 10 seconds
      myRateLimiter.init(2,10);

      // Syntax: check(timestamp, count)
      bool r = myRateLimiter.check(now(), 1);
      // check call returns true if allowed

      // Default count is one (1)
      r = myRateLimiter.check(now());

      // Alternatively use DateTime ...
      r = myRateLimiter.check(DateTime(2020, 1, 1, 0, 0, 0), 1);

      // ... or SysTime timestamp
      r = myRateLimiter.check(Clock.currTime(), 1);

------------
### Rate limiter map
  Usage:

      RateLimiterBucketMap myRateLimiterMap;

      // Syntax: init(count, duration)
      // Allow 2 units per 10 seconds
      myRateLimiterMap.init(2,10);

      // Syntax: check(key, timestamp, count)
      // Here using static "abc" string as key
      // Common choices for keys are IP addresses and usernames
      bool r = myRateLimiterMap.check("abc", now(), 1);
      // check call returns true if allowed

      // Default count is one (1)
      r = myRateLimiterMap.check("abc", now());

      // Alternatively use DateTime ...
      r = myRateLimiterMap.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);

      // ... or SysTime timestamp
      r = myRateLimiter.check("abc", Clock.currTime(), 1);

      // Optionally perform garbage collection if needed
      // Be aware of run time, which may be too long for some applications
      // Syntax: performGarbageCollection(timestamp)
      myRateLimiterMap.performGarbageCollection(now());

  In order to remove seldom used entries the following approached is used:
  When an existing bucket is empty (i.e. no action for a some time) and a check is performed with a count of exactly 1, the bucket is deleted.

------------
### Rate limiter sketch
  Usage:

      RateLimiterBucketSketch myRateLimiterSketch;

      // Syntax: init(count, duration, rows, columns)
      // Allow 2 units per 10 seconds
      // Use sketch with 2 rows (i.e. 3 hash functions) and 5 columns (i.e. use computed hash values modulus 5)
      myRateLimiterSketch.init(2, 10, 3, 5);

      // Syntax: check(key, timestamp, count)
      // Here using static "abc" string as key
      // Common choices for keys are IP addresses and usernames
      bool r = myRateLimiterSketch.check("abc", now(), 1);
      // check call returns true if allowed

      // Default count is one (1)
      r = myRateLimiterSketch.check("abc", now());

      // Alternatively use DateTime ...
      r = myRateLimiterSketch.check("abc", DateTime(2020, 1, 1, 0, 0, 0), 1);

      // ... or SysTime timestamp
      r = myRateLimiterSketch.check("abc", Clock.currTime(), 1);
