id: fc5gebkr7krkoco6izonvfvnxicvzto99z1d0u6kooda5kgd
name: apple_pie
main: src/apple_pie.zig
dependencies:
- type: git
  path: https://github.com/lithdew/pike
  name: pike
  main: pike.zig
- type: git
  path: https://github.com/kprotty/zap
  version: commit-55eea90dedc34e010b2694e962d13452aa30b63c
  name: zap
  main: src/zap.zig

