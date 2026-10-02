#include <iostream>
#include <string>
#include <string_view>

int main()
{
        const std::string message = "hello-cmake";
        if (std::string_view{ message } != std::string_view{ "hello-cmake" }) {
                return 1;
        }
        std::cout << message << '\n';
        return 0;
}
