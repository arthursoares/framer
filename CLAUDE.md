# Framer Project Guidelines

## Build Commands
- Build: `go build framer.go fonts.go`
- Run: `./framer -i /path/to/image.jpg -o /path/to/output_folder`
- Embed fonts: `$(go env GOPATH)/bin/go-bindata -pkg main -o fonts.go fonts_data/`
- List fonts: `./framer --list-fonts`

## Code Style Guidelines
- **Formatting**: Standard Go formatting with `gofmt`
- **Imports**: Group stdlib imports first, then third-party packages
- **Error handling**: Always check errors and provide descriptive messages
- **Variable naming**: Use camelCase for variables, PascalCase for exported functions
- **Functions**: Keep functions short, focused on a single responsibility
- **Comments**: Document public functions and complex logic
- **Types**: Use strong typing; avoid interface{} where possible
- **File organization**: Group related functionality in logical sections
- **Constants**: Define constants for magic values
- **Testing**: Write tests for core functionality