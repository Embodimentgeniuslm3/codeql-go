/**
 * Provides a library for writing QL tests whose success or failure is based on expected results
 * embedded in the test source code as comments, rather than a `.expected` file.
 *
 * To add this framework to a new language:
 * - Add a file `InlineExpectationsTestPrivate.qll` that defines a `ExpectationComment` class. This class
 *   must support a `getContents` method that returns the contents of the given comment, _excluding_
 *   the comment indicator itself. It should also define `toString` and `getLocation` as usual.
 *
 * To create a new inline expectations test:
 * - Declare a class that extends `InlineExpectationsTest`. In the characteristic predicate of the
 * new class, bind `this` to a unique string (usually the name of the test).
 * - Override the `hasActualResult()` predicate to produce the actual results of the query. For each
 * result, specify a `Location`, a text description of the element for which the result was
 * reported, a short string to serve as the tag to identify expected results for this test, and the
 * expected value of the result.
 * - Override `getARelevantTag()` to return the set of tags that can be produced by
 * `hasActualResult()`. Often this is just a single tag.
 *
 * Example:
 * ```ql
 * class ConstantValueTest extends InlineExpectationsTest {
 *   ConstantValueTest() { this = "ConstantValueTest" }
 *
 *   override string getARelevantTag() {
 *     // We only use one tag for this test.
 *     result = "const"
 *   }
 *
 *   override predicate hasActualResult(
 *     Location location, string element, string tag, string value
 *   ) {
 *     exists(Expr e |
 *       tag = "const" and // The tag for this test.
 *       value = e.getValue() and // The expected value. Will only hold for constant expressions.
 *       location = e.getLocation() and // The location of the result to be reported.
 *       element = e.toString() // The display text for the result.
 *     )
 *   }
 * }
 * ```
 *
 * There is no need to write a `select` clause or query predicate. All of the differences between
 * expected results and actual results will be reported in the `failures()` query predicate.
 *
 * To annotate the test source code with an expected result, place a comment on the
 * same line as the expected result, with text of the following format as the body of the comment:
 *
 * `$tag=expected-value`
 *
 * Where `tag` is the value of the `tag` parameter from `hasActualResult()`, and `expected-value` is
 * the value of the `value` parameter from `hasActualResult()`. The `=expected-value` portion may be
 * omitted, in which case `expected-value` is treated as the empty string. Multiple expectations may
 * be placed in the same comment, as long as each is prefixed by a `$`. Any actual result that
 * appears on a line that does not contain a matching expected result comment will be reported with
 * a message of the form "Unexpected result: tag=value". Any expected result comment for which there
 * is no matching actual result will be reported with a message of the form
 * "Missing result: tag=expected-value".
 *
 * Example:
 * ```cpp
 * int i = x + 5;  // $const=5
 * int j = y + (7 - 3)  // $const=7 $const=3 $const=4  // The result of the subtraction is a constant.
 * ```
 *
 * For tests that contain known false positives and false negatives, it is possible to further
 * annotate that a particular expected result is known to be a false positive, or that a particular
 * missing result is known to be a false negative:
 *
 * `$f+:tag=expected-value`  // False positive
 * `$f-:tag=expected-value`  // False negative
 *
 * A false positive expectation is treated as any other expected result, except that if there is no
 * matching actual result, the message will be of the form "Fixed false positive: tag=value". A
 * false negative expectation is treated as if there were no expected result, except that if a
 * matching expected result is found, the message will be of the form
 * "Fixed false negative: tag=value".
 *
 * If the same result value is expected for two or more tags on the same line, there is a shorthand
 * notation available:
 *
 * `$tag1,tag2=expected-value`
 *
 * is equivalent to:
 *
 * `$tag1=expected-value $tag2=expected-value`
 */

private import InlineExpectationsTestPrivate

/**
 * Base class for tests with inline expectations. The test extends this class to provide the actual
 * results of the query, which are then compared with the expected results in comments to produce a
 * list of failure messages that point out where the actual results differ from the expected
 * results.
 */
abstract class InlineExpectationsTest extends string {
  bindingset[this]
  InlineExpectationsTest() { any() }

  /**
   * Returns all tags that can be generated by this test. Most tests will only ever produce a single
   * tag. Any expected result comments for a tag that is not returned by the `getARelevantTag()`
   * predicate for an active test will be ignored. This makes it possible to write multiple tests in
   * different `.ql` files that all query the same source code.
   */
  abstract string getARelevantTag();

  /**
   * Returns the actual results of the query that is being tested. Each result consist of the
   * following values:
   * - `location` - The source code location of the result. Any expected result comment must appear
   *   on the start line of this location.
   * - `element` - Display text for the element on which the result is reported.
   * - `tag` - The tag that marks this result as coming from this test. This must be one of the tags
   *   returned by `getARelevantTag()`.
   * - `value` - The value of the result, which will be matched against the value associated with
   *   `tag` in any expected result comment on that line.
   */
  abstract predicate hasActualResult(string file, int line, string element, string tag, string value);

  final predicate hasFailureMessage(FailureLocatable element, string message) {
    exists(ActualResult actualResult |
      actualResult.getTest() = this and
      element = actualResult and
      (
        exists(FalseNegativeExpectation falseNegative |
          falseNegative.matchesActualResult(actualResult) and
          message = "Fixed false negative:" + falseNegative.getExpectationText()
        )
        or
        not exists(ValidExpectation expectation | expectation.matchesActualResult(actualResult)) and
        message = "Unexpected result: " + actualResult.getExpectationText()
      )
    )
    or
    exists(ValidExpectation expectation |
      not exists(ActualResult actualResult | expectation.matchesActualResult(actualResult)) and
      expectation.getTag() = this.getARelevantTag() and
      element = expectation and
      (
        expectation instanceof GoodExpectation and
        message = "Missing result:" + expectation.getExpectationText()
        or
        expectation instanceof FalsePositiveExpectation and
        message = "Fixed false positive:" + expectation.getExpectationText()
      )
    )
    or
    exists(InvalidExpectation expectation |
      element = expectation and
      message = "Invalid expectation syntax: " + expectation.getExpectation()
    )
  }
}

/**
 * RegEx pattern to match a comment containing one or more expected results. The comment must have
 * `$` as its first non-whitespace character. Any subsequent character
 * is treated as part of the expected results, except that the comment may contain a `//` sequence
 * to treat the remainder of the line as a regular (non-interpreted) comment.
 */
private string expectationCommentPattern() { result = "\\s*(\\$(?:[^/]|/[^/])*)(?://.*)?" }

/**
 * RegEx pattern to match a single expected result, not including the leading `$`. It starts with an
 * optional `f+:` or `f-:`, followed by one or more comma-separated tags containing only letters,
 * `-`, and `_`, optionally followed by `=` and the expected value.
 */
private string expectationPattern() {
  result = "(?:(f(?:\\+|-)):)?((?:[A-Za-z-_]+)(?:\\s*,\\s*[A-Za-z-_]+)*)(?:=(.*))?"
}

private string getAnExpectation(ExpectationComment comment) {
  result = comment.getContents().regexpCapture(expectationCommentPattern(), 1).splitAt("$").trim() and
  result != ""
}

private newtype TFailureLocatable =
  TActualResult(
    InlineExpectationsTest test, string file, int line, string element, string tag, string value
  ) {
    test.hasActualResult(file, line, element, tag, value)
  } or
  TValidExpectation(ExpectationComment comment, string tag, string value, string knownFailure) {
    exists(string expectation |
      expectation = getAnExpectation(comment) and
      expectation.regexpMatch(expectationPattern()) and
      tag = expectation.regexpCapture(expectationPattern(), 2).splitAt(",").trim() and
      (
        if exists(expectation.regexpCapture(expectationPattern(), 3))
        then value = expectation.regexpCapture(expectationPattern(), 3)
        else value = ""
      ) and
      (
        if exists(expectation.regexpCapture(expectationPattern(), 1))
        then knownFailure = expectation.regexpCapture(expectationPattern(), 1)
        else knownFailure = ""
      )
    )
  } or
  TInvalidExpectation(ExpectationComment comment, string expectation) {
    expectation = getAnExpectation(comment) and
    not expectation.regexpMatch(expectationPattern())
  }

class FailureLocatable extends TFailureLocatable {
  string toString() { none() }

  predicate hasLocation(string file, int line) { none() }

  final string getExpectationText() { result = this.getTag() + "=" + this.getValue() }

  string getTag() { none() }

  string getValue() { none() }
}

class ActualResult extends FailureLocatable, TActualResult {
  InlineExpectationsTest test;
  string file;
  int line;
  string element;
  string tag;
  string value;

  ActualResult() { this = TActualResult(test, file, line, element, tag, value) }

  override string toString() { result = element }

  override predicate hasLocation(string f, int l) { f = file and l = line }

  InlineExpectationsTest getTest() { result = test }

  override string getTag() { result = tag }

  override string getValue() { result = value }
}

abstract private class Expectation extends FailureLocatable {
  ExpectationComment comment;

  override string toString() { result = comment.toString() }

  override predicate hasLocation(string file, int line) {
    comment.hasLocationInfo(file, line, _, _, _)
  }
}

private class ValidExpectation extends Expectation, TValidExpectation {
  string tag;
  string value;
  string knownFailure;

  ValidExpectation() { this = TValidExpectation(comment, tag, value, knownFailure) }

  override string getTag() { result = tag }

  override string getValue() { result = value }

  string getKnownFailure() { result = knownFailure }

  predicate matchesActualResult(ActualResult actualResult) {
    exists(string file, int line | actualResult.hasLocation(file, line) |
      this.hasLocation(file, line)
    ) and
    this.getTag() = actualResult.getTag() and
    this.getValue() = actualResult.getValue()
  }
}

class GoodExpectation extends ValidExpectation {
  GoodExpectation() { this.getKnownFailure() = "" }
}

class FalsePositiveExpectation extends ValidExpectation {
  FalsePositiveExpectation() { this.getKnownFailure() = "f+" }
}

class FalseNegativeExpectation extends ValidExpectation {
  FalseNegativeExpectation() { this.getKnownFailure() = "f-" }
}

class InvalidExpectation extends Expectation, TInvalidExpectation {
  string expectation;

  InvalidExpectation() { this = TInvalidExpectation(comment, expectation) }

  string getExpectation() { result = expectation }
}

query predicate failures(string file, int line, FailureLocatable element, string message) {
  exists(InlineExpectationsTest test | test.hasFailureMessage(element, message) |
    element.hasLocation(file, line)
  )
}
