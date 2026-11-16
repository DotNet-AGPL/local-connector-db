using MongoDB.Bson;

namespace Connector.Mongo;

/// <summary>
/// 解析 `collection.method(args...)` / `db.method(args...)`。
/// 参数是宽松的 JSON / JS 字面量：键可不加引号、可用单引号；
/// 同时支持 MongoDB 扩展 JSON 的 $oid / $date / $numberLong。
/// </summary>
internal sealed class MongoCommand
{
    private MongoCommand(string target, string method, List<BsonValue> arguments)
    {
        Target = target;
        Method = method;
        Arguments = arguments;
    }

    public string Target { get; }

    public string Method { get; }

    public bool IsDatabaseCommand => string.Equals(Target, "db", StringComparison.Ordinal);

    public List<BsonValue> Arguments { get; }

    public static MongoCommand Parse(string text)
    {
        var parser = new Parser(text);

        var target = parser.ReadIdentifier();
        parser.Expect('.');

        var method = parser.ReadIdentifier();
        parser.Expect('(');

        var arguments = new List<BsonValue>();

        parser.SkipWhitespace();

        if (!parser.TryConsume(')'))
        {
            while (true)
            {
                arguments.Add(parser.ReadValue());
                parser.SkipWhitespace();

                if (parser.TryConsume(')'))
                {
                    break;
                }

                parser.Expect(',');
            }
        }

        parser.EnsureEnd();

        return new MongoCommand(target, method, arguments);
    }

    private sealed class Parser(string text)
    {
        private int _position;

        public void SkipWhitespace()
        {
            while (_position < text.Length && char.IsWhiteSpace(text[_position]))
            {
                _position++;
            }
        }

        public bool TryConsume(char character)
        {
            SkipWhitespace();

            if (_position < text.Length && text[_position] == character)
            {
                _position++;
                return true;
            }

            return false;
        }

        public void Expect(char character)
        {
            if (!TryConsume(character))
            {
                throw new FormatException($"命令格式错误：期望 '{character}'（位置 {_position}）");
            }
        }

        public void EnsureEnd()
        {
            SkipWhitespace();

            while (_position < text.Length && text[_position] == ';')
            {
                _position++;
                SkipWhitespace();
            }

            if (_position < text.Length)
            {
                throw new FormatException($"命令格式错误：位置 {_position} 处有多余内容");
            }
        }

        public string ReadIdentifier()
        {
            SkipWhitespace();

            var start = _position;

            while (_position < text.Length && (char.IsLetterOrDigit(text[_position]) || text[_position] is '_' or '$'))
            {
                _position++;
            }

            if (start == _position)
            {
                throw new FormatException($"命令格式错误：期望标识符（位置 {_position}）");
            }

            return text[start.._position];
        }

        public BsonValue ReadValue()
        {
            SkipWhitespace();

            if (_position >= text.Length)
            {
                throw new FormatException("命令格式错误：内容意外结束");
            }

            var character = text[_position];

            return character switch
            {
                '{' => ReadObject(),
                '[' => ReadArray(),
                '"' or '\'' => new BsonString(ReadString()),
                _ => ReadScalar(),
            };
        }

        private BsonValue ReadObject()
        {
            Expect('{');

            var document = new BsonDocument();
            SkipWhitespace();

            if (TryConsume('}'))
            {
                return document;
            }

            while (true)
            {
                SkipWhitespace();

                var key = _position < text.Length && text[_position] is '"' or '\''
                    ? ReadString()
                    : ReadIdentifier();

                Expect(':');
                document[key] = ReadValue();
                SkipWhitespace();

                if (TryConsume('}'))
                {
                    break;
                }

                Expect(',');
            }

            return UnwrapExtendedJson(document);
        }

        private BsonValue ReadArray()
        {
            Expect('[');

            var array = new BsonArray();
            SkipWhitespace();

            if (TryConsume(']'))
            {
                return array;
            }

            while (true)
            {
                array.Add(ReadValue());
                SkipWhitespace();

                if (TryConsume(']'))
                {
                    break;
                }

                Expect(',');
            }

            return array;
        }

        private string ReadString()
        {
            var quote = text[_position++];
            var builder = new System.Text.StringBuilder();

            while (_position < text.Length)
            {
                var character = text[_position++];

                if (character == quote)
                {
                    return builder.ToString();
                }

                if (character != '\\')
                {
                    builder.Append(character);
                    continue;
                }

                if (_position >= text.Length)
                {
                    break;
                }

                var escaped = text[_position++];
                builder.Append(escaped switch
                {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    'b' => '\b',
                    'f' => '\f',
                    'u' => ReadUnicode(),
                    _ => escaped,
                });
            }

            throw new FormatException("命令格式错误：字符串未闭合");
        }

        private char ReadUnicode()
        {
            var hex = text.Substring(_position, 4);
            _position += 4;
            return (char)Convert.ToInt32(hex, 16);
        }

        private BsonValue ReadScalar()
        {
            var start = _position;

            while (_position < text.Length &&
                   text[_position] is not (' ' or '\t' or '\r' or '\n' or ',' or ')' or ']' or '}'))
            {
                _position++;
            }

            var token = text[start.._position];

            if (token.Length == 0)
            {
                throw new FormatException($"命令格式错误：位置 {start} 处无法识别的值");
            }

            return token switch
            {
                "true" => BsonBoolean.True,
                "false" => BsonBoolean.False,
                "null" or "undefined" => BsonNull.Value,
                _ => ParseNumber(token),
            };
        }

        private static BsonValue ParseNumber(string token)
        {
            if (token.Contains('.') || token.Contains('e') || token.Contains('E'))
            {
                return new BsonDouble(double.Parse(token, System.Globalization.CultureInfo.InvariantCulture));
            }

            if (int.TryParse(token, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var intValue))
            {
                return new BsonInt32(intValue);
            }

            if (long.TryParse(token, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var longValue))
            {
                return new BsonInt64(longValue);
            }

            throw new FormatException($"命令格式错误：无法识别的数字 {token}");
        }

        /// <summary>扩展 JSON：{"$oid": "..."} / {"$date": "..."} / {"$numberLong": "..."}。</summary>
        private static BsonValue UnwrapExtendedJson(BsonDocument document)
        {
            if (document.ElementCount != 1)
            {
                return document;
            }

            var element = document.GetElement(0);
            var value = element.Value;

            switch (element.Name)
            {
                case "$oid" when value.IsString:
                    return new BsonObjectId(ObjectId.Parse(value.AsString));
                case "$numberLong" when value.IsString:
                    return new BsonInt64(long.Parse(value.AsString, System.Globalization.CultureInfo.InvariantCulture));
                case "$date" when value.IsString:
                    return new BsonDateTime(DateTime.Parse(value.AsString, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal));
                case "$date" when value.IsNumeric:
                    return new BsonDateTime(DateTimeOffset.FromUnixTimeMilliseconds(value.ToInt64()).UtcDateTime);
                default:
                    return document;
            }
        }
    }
}
