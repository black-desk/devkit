#include <sstream>

#include <json/json.h>
int main()
{
        Json::Value value;
        std::istringstream input("{\"answer\":42}");
        input >> value;
        if (value["answer"].asInt() != 42)
                return 1;
        Json::StreamWriterBuilder writer;
        auto encoded = Json::writeString(writer, value);
        return encoded.find("42") == std::string::npos;
}
