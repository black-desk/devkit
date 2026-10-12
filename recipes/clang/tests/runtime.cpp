#include <stdexcept>
#include <vector>
int main()
{
        std::vector<int> values{ 1, 2, 3 };
        try {
                throw std::runtime_error("runtime");
        } catch (const std::exception &) {
                return values.at(2) == 3 ? 0 : 1;
        }
}
