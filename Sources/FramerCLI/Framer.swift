import ArgumentParser

@main
struct Framer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "framer",
        abstract: "Add borders and captions to photos",
        subcommands: [ProcessCommand.self, PresetsCommand.self, FontsCommand.self, BenchmarkCommand.self],
        defaultSubcommand: ProcessCommand.self
    )
}
