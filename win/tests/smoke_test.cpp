#include <iostream>
#include <string>

#include "core/version.h"

int main() {
  const std::string v = sclip::core::version();
  if (v != "2.0.0") {
    std::cerr << "unexpected core version: " << v << "\n";
    return 1;
  }
  return 0;
}
