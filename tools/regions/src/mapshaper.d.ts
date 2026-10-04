declare module 'mapshaper' {
  const mapshaper: {
    applyCommands(commands: string, input: Record<string, unknown>): Promise<unknown>;
  };
  export default mapshaper;
}
