import HokusaiCommandLine

/// The `hokusai` executable: only the process entry point. Everything the
/// command does lives in `HokusaiCommandLine`.
@main
struct HokusaiCLI {
    static func main() async {
        await HokusaiRootCommand.main()
    }
}
