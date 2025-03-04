import Foundation
import PackagePlugin

@main
struct SwiftLintPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else {
            // Don't lint anything when running in for Xcode previews
            return []
        }

        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }
        return createBuildCommands(
            inputFiles: sourceTarget.sourceFiles(withSuffix: "swift").map(\.path),
            packageDirectory: context.package.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: try context.tool(named: "swiftlint")
        )
    }

    private func createBuildCommands(
        inputFiles: [Path],
        packageDirectory: Path,
        workingDirectory: Path,
        tool: PluginContext.Tool
    ) -> [Command] {
        if inputFiles.isEmpty {
            // Don't lint anything if there are no Swift source files in this target
            return []
        }

        var arguments = [
            "lint",
            "--quiet",
            // We always pass all of the Swift source files in the target to the tool,
            // so we need to ensure that any exclusion rules in the configuration are
            // respected.
            "--force-exclude"
        ]

        // Determine whether we need to enable cache or not (for Xcode Cloud we don't)
        if ProcessInfo.processInfo.environment["CI_XCODE_CLOUD"] == "TRUE" {
            arguments.append("--no-cache")
        } else {
            arguments.append("--cache-path")
            arguments.append("\(workingDirectory)")
        }

        // Manually look for configuration files, to avoid issues when the plugin does not execute our tool from the
        // package source directory.
        if let configuration = packageDirectory.firstConfigurationFileInParentDirectories() {
            arguments.append(contentsOf: ["--config", "\(configuration.string)"])
        }
        arguments += inputFiles.map(\.string)

        // We are not producing output files and this is needed only to not include cache files into bundle
        let outputFilesDirectory = workingDirectory.appending("Output")

        return [
            .prebuildCommand(
                displayName: "SwiftLint",
                executable: tool.path,
                arguments: arguments,
                outputFilesDirectory: outputFilesDirectory
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLintPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let inputFilePaths = target.inputFiles
            .filter { $0.type == .source && $0.path.extension == "swift" }
            .map(\.path)
        return createBuildCommands(
            inputFiles: inputFilePaths,
            packageDirectory: context.xcodeProject.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: try context.tool(named: "swiftlint")
        )
    }
}
#endif
