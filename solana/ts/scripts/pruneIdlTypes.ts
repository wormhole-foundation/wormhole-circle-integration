import * as fs from "fs";

const BASENAME = "wormhole_circle_integration_solana";

const ROOT = `${__dirname}/../..`;
const TYPES = `${ROOT}/target/types/${BASENAME}.ts`;

const IGNORE_TYPES = [
    '"name": "LocalToken"',
    '"name": "TokenPair"',
    '"name": "MessageTransmitterConfig"',
    '"name": "WormholeCctp"',
];

main();

function main() {
    if (!fs.existsSync(TYPES)) {
        throw new Error("Types non-existent");
    }

    const types = fs.readFileSync(TYPES, "utf8").split("\n");
    for (const matchStr of IGNORE_TYPES) {
        while (spliceType(types, matchStr));
    }
    fs.writeFileSync(TYPES, types.join("\n"), "utf8");
}

function spliceType(lines: string[], matchStr: string) {
    let lineNumber = 0;
    let start = -1;
    let spaces = -1;
    for (const line of lines) {
        if (line.includes(matchStr)) {
            start = lineNumber - 1;
            spaces = line.indexOf('"') - 2;
        } else if (start > -1) {
            if (line == "}".padStart(spaces + 1, " ")) {
                lines[start - 1] = lines[start - 1].replace("},", "}");
                lines.splice(start, lineNumber - start + 1);
                return true;
            } else if (line == "},".padStart(spaces + 2, " ")) {
                lines.splice(start, lineNumber - start + 1);
                return true;
            }
        }
        ++lineNumber;
    }

    return false;
}
