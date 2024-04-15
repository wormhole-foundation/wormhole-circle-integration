import * as fs from "fs";

const BASENAME = "wormhole_circle_integration_solana";

const ROOT = `${__dirname}/../..`;
const IDL = `${ROOT}/target/idl/${BASENAME}.json`;
const TYPES = `${ROOT}/target/types/${BASENAME}.ts`;

const IGNORE_TYPES = [
    // '"name": "LocalToken"',
    // '"name": "TokenPair"',
    // '"name": "MessageTransmitterConfig"',
    // '"name": "WormholeCctp"',
    //'"name": "ExternalAccount"',
];

main();

function main() {
    for (const fn of [IDL, TYPES]) {
        if (!fs.existsSync(fn)) {
            throw new Error(`${fn} non-existent`);
        }

        const types = fs.readFileSync(fn, "utf8").split("\n");
        for (const matchStr of IGNORE_TYPES) {
            while (spliceType(types, matchStr));
        }
        fs.writeFileSync(fn, types.join("\n"), "utf8");
    }
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
