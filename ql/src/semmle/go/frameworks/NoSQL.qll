/**
 * Provides classes for working with NoSQL-related concepts such as queries.
 */

import go

/** Provides classes for working with NoSQL-related APIs. */
module NoSQL {
  /**
   * A data-flow node whose string value is interpreted as (part of) a NoSQL query.
   *
   * Extend this class to refine existing API models. If you want to model new APIs,
   * extend `NoSQL::QueryString::Range` instead.
   */
  class NoSQLQueryString extends DataFlow::Node {
    NoSQLQueryString::Range self;

    NoSQLQueryString() { this = self }
  }

  /** Provides classes for working with SQL query strings. */
  module NoSQLQueryString {
    /**
     * A data-flow node whose string value is interpreted as (part of) a NoSQL query.
     *
     * Extend this class to model new APIs. If you want to refine existing API models,
     * extend `NoSQL::QueryString` instead.
     */
    abstract class Range extends DataFlow::Node { }

    /**
     * Holds if method `name` of `Collection` struct of `go.mongodb.org/mongo-driver/mongo`
     * package interprets parameter `n` as a query.
     */
    private predicate collectionMethods(string name, int n) {
      // func (coll *Collection) CountDocuments(ctx context.Context, filter interface{}, opts ...*options.CountOptions) (int64, error)
      name = "CountDocuments" and n = 1
      or
      // func (coll *Collection) DeleteMany(ctx context.Context, filter interface{}, opts ...*options.DeleteOptions) (*DeleteResult, error)
      name = "DeleteMany" and n = 1
      or
      // func (coll *Collection) DeleteOne(ctx context.Context, filter interface{}, opts ...*options.DeleteOptions) (*DeleteResult, error)
      name = "DeleteOne" and n = 1
      or
      // func (coll *Collection) Distinct(ctx context.Context, fieldName string, filter interface{}, ...) ([]interface{}, error)
      name = "Distinct" and n = 2
      or
      // func (coll *Collection) Find(ctx context.Context, filter interface{}, opts ...*options.FindOptions) (*Cursor, error)
      name = "Find" and n = 1
      or
      // func (coll *Collection) FindOne(ctx context.Context, filter interface{}, opts ...*options.FindOneOptions) *SingleResult
      name = "FindOne" and n = 1
      or
      // func (coll *Collection) FindOneAndDelete(ctx context.Context, filter interface{}, ...) *SingleResult
      name = "FindOneAndDelete" and n = 1
      or
      // func (coll *Collection) FindOneAndReplace(ctx context.Context, filter interface{}, replacement interface{}, ...) *SingleResult
      name = "FindOneAndReplace" and n = 1
      or
      // func (coll *Collection) FindOneAndUpdate(ctx context.Context, filter interface{}, update interface{}, ...) *SingleResult
      name = "FindOneAndUpdate" and n = 1
      or
      // func (coll *Collection) ReplaceOne(ctx context.Context, filter interface{}, replacement interface{}, ...) (*UpdateResult, error)
      name = "ReplaceOne" and n = 1
      or
      // func (coll *Collection) UpdateMany(ctx context.Context, filter interface{}, update interface{}, ...) (*UpdateResult, error)
      name = "UpdateMany" and n = 1
      or
      // func (coll *Collection) UpdateOne(ctx context.Context, filter interface{}, update interface{}, ...) (*UpdateResult, error)
      name = "UpdateOne" and n = 1
      or
      // func (coll *Collection) Watch(ctx context.Context, pipeline interface{}, ...) (*ChangeStream, error)
      name = "Watch" and n = 1
      or
      // func (coll *Collection) Aggregate(ctx context.Context, pipeline interface{}, opts ...*options.AggregateOptions) (*Cursor, error)
      name = "Aggregate" and n = 1
    }

    /**
     * A query string used in an API function acting on a `Collection` struct of
     * `go.mongodb.org/mongo-driver/mongo` package
     */
    private class MongoDbCollectionQueryString extends Range {
      MongoDbCollectionQueryString() {
        exists(Method meth, string methodName, int n |
          collectionMethods(methodName, n) and
          meth.hasQualifiedName("go.mongodb.org/mongo-driver/mongo", "Collection", methodName) and
          this = meth.getACall().getArgument(n)
        )
      }
    }
  }

  /**
   * Holds if taint flows from `pred` to `succ` through a MongoDB-specific API.
   */
  predicate isAdditionalMongoTaintStep(DataFlow::Node pred, DataFlow::Node succ) {
    // Taint an entry if the `Value` is tainted
    exists(Write w, DataFlow::Node base, Field f | w.writesField(base, f, pred) |
      base = succ.getASuccessor*() and
      base.getType().hasQualifiedName("go.mongodb.org/mongo-driver/bson/primitive", "E") and
      f.getName() = "Value"
    )
  }
}