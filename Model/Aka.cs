using Microsoft.Azure.Cosmos.Table;

namespace LinkRedirector.Model
{
    public class Aka : TableEntity
    {
        public const string DefaultPartitionKey = "aka";
        public const string DefaultRowKey = "400";

        public Aka(string partitionKey, string rowKey) : base(partitionKey, rowKey)
        {
        }

        public Aka() : this(DefaultPartitionKey, DefaultRowKey)
        {
        }

        public string Url { get; set; }
    }
}