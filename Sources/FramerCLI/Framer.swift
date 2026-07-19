import ArgumentParser

@main
struct Framer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "framer",
        abstract: "Add borders and captions to photos",
        // Release ceremony (.claude/skills/release/SKILL.md) bumps this
        // together with CHANGELOG.md and both MARKETING_VERSIONs in project.yml.
        version: "2.1.0",
        subcommands: [ProcessCommand.self, PresetsCommand.self, FontsCommand.self, BenchmarkCommand.self],
        defaultSubcommand: ProcessCommand.self
    )
}
