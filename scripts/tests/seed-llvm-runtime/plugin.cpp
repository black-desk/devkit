#include <stdexcept>
extern "C" void throw_from_plugin()
{
        throw std::runtime_error("plugin");
}
