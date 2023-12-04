import { ethers } from "ethers";

export function findCircleMessageInLogs(
    logs: ethers.providers.Log[],
    messageTransmitterAddress: string
): string | null {
    for (const log of logs) {
        if (log.address == messageTransmitterAddress) {
            const iface = new ethers.utils.Interface(["event MessageSent(bytes message)"]);
            return iface.parseLog(log).args.message as string;
        }
    }

    return null;
}
