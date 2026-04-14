import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.net.SocketTimeoutException;
import java.util.concurrent.ConcurrentLinkedQueue;

import brainflow.*;
import org.apache.commons.lang3.tuple.ImmutablePair;
import org.apache.commons.lang3.tuple.Pair;

class BoardNeuro11UDP extends Board {

    private static final int EXPECTED_PACKET_SIZE = 33;
    private static final int MAX_PACKETS_PER_UPDATE = 1000;

    private final ConcurrentLinkedQueue<double[]> pendingSamples = new ConcurrentLinkedQueue<double[]>();
    private final boolean[] channelActive = new boolean[NCHAN_CYTON];

    private DatagramSocket udpSocket = null;
    private boolean connected = false;
    private boolean streaming = false;

    private final String bindIp;
    private final int bindPort;

    private int sampleRateCache = 250;
    private int[] exgChannelsCache = null;
    private int[] accelChannelsCache = null;
    private int timestampChannelCache = -1;
    private int sampleIndexChannelCache = -1;
    private int markerChannelCache = -1;
    private int totalChannelsCache = -1;

    public BoardNeuro11UDP(String ip, int port) {
        bindIp = (ip == null || ip.trim().length() == 0) ? "127.0.0.1" : ip.trim();
        bindPort = port;
        for (int i = 0; i < channelActive.length; i++) {
            channelActive[i] = true;
        }
    }

    @Override
    protected boolean initializeInternal() {
        if (bindPort <= 0 || bindPort > 65535) {
            outputError("OpenBCI_GUI: Invalid Neuro11 UDP port: " + bindPort);
            return false;
        }

        try {
            udpSocket = new DatagramSocket(new InetSocketAddress(bindIp, bindPort));
            udpSocket.setReuseAddress(true);
            udpSocket.setSoTimeout(1);
            connected = true;
            println("OpenBCI_GUI: Neuro11 UDP listener bound to " + bindIp + ":" + bindPort);
            return true;
        } catch (Exception e) {
            outputError("OpenBCI_GUI: Failed to bind Neuro11 UDP listener on " + bindIp + ":" + bindPort + " - " + e);
            e.printStackTrace();
            connected = false;
            return false;
        }
    }

    @Override
    protected void uninitializeInternal() {
        streaming = false;
        connected = false;
        pendingSamples.clear();
        if (udpSocket != null) {
            udpSocket.close();
            udpSocket = null;
        }
    }

    @Override
    public void startStreaming() {
        super.startStreaming();
        streaming = true;
    }

    @Override
    public void stopStreaming() {
        super.stopStreaming();
        streaming = false;
        pendingSamples.clear();
    }

    @Override
    protected void updateInternal() {
        if (!streaming || udpSocket == null) {
            return;
        }

        byte[] buffer = new byte[64];
        for (int i = 0; i < MAX_PACKETS_PER_UPDATE; i++) {
            DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
            try {
                udpSocket.receive(packet);
                if (packet.getLength() != EXPECTED_PACKET_SIZE) {
                    continue;
                }
                double[] parsed = parseCytonPacket(packet.getData(), packet.getLength());
                if (parsed != null) {
                    pendingSamples.add(parsed);
                }
            } catch (SocketTimeoutException timeout) {
                break;
            } catch (Exception e) {
                outputWarn("OpenBCI_GUI: Neuro11 UDP receive warning: " + e.getMessage());
                break;
            }
        }
    }

    @Override
    protected double[][] getNewDataInternal() {
        int sampleCount = pendingSamples.size();
        if (sampleCount <= 0) {
            return emptyData;
        }

        double[][] data = new double[getTotalChannelCount()][sampleCount];
        for (int i = 0; i < sampleCount; i++) {
            double[] sample = pendingSamples.poll();
            if (sample == null) {
                break;
            }
            for (int row = 0; row < getTotalChannelCount(); row++) {
                data[row][i] = sample[row];
            }
        }
        return data;
    }

    private double[] parseCytonPacket(byte[] packet, int length) {
        if (length < EXPECTED_PACKET_SIZE) {
            return null;
        }
        if ((packet[0] & 0xFF) != 0xA0) {
            return null;
        }

        int[] exg = getEXGChannels();
        if (exg.length < NCHAN_CYTON) {
            return null;
        }

        double[] row = new double[getTotalChannelCount()];

        int sampleIndex = packet[1] & 0xFF;
        row[getSampleIndexChannel()] = sampleIndex;
        row[getTimestampChannel()] = System.currentTimeMillis() / 1000.0;
        row[getMarkerChannel()] = 0.0;

        for (int ch = 0; ch < NCHAN_CYTON; ch++) {
            int off = 2 + ch * 3;
            int raw = parseSigned24(packet[off], packet[off + 1], packet[off + 2]);
            double microvolts = raw * BoardCytonConstants.scale_fac_uVolts_per_count;
            row[exg[ch]] = channelActive[ch] ? microvolts : 0.0;
        }

        int[] accel = getAccelerometerChannels();
        for (int i = 0; i < min(accel.length, NUM_ACCEL_DIMS); i++) {
            int off = 26 + i * 2;
            int raw = parseSigned16(packet[off], packet[off + 1]);
            row[accel[i]] = raw * BoardCytonConstants.accelScale;
        }

        return row;
    }

    private int parseSigned24(byte b1, byte b2, byte b3) {
        int value = ((b1 & 0xFF) << 16) | ((b2 & 0xFF) << 8) | (b3 & 0xFF);
        if ((value & 0x00800000) != 0) {
            value |= 0xFF000000;
        }
        return value;
    }

    private int parseSigned16(byte b1, byte b2) {
        int value = ((b1 & 0xFF) << 8) | (b2 & 0xFF);
        if ((value & 0x8000) != 0) {
            value |= 0xFFFF0000;
        }
        return value;
    }

    @Override
    public boolean isConnected() {
        return connected;
    }

    @Override
    public boolean isStreaming() {
        return streaming;
    }

    @Override
    public int getSampleRate() {
        return sampleRateCache;
    }

    @Override
    public int[] getEXGChannels() {
        if (exgChannelsCache == null) {
            try {
                exgChannelsCache = BoardShim.get_eeg_channels(BoardIds.CYTON_BOARD.get_code());
            } catch (Exception e) {
                exgChannelsCache = new int[] {1, 2, 3, 4, 5, 6, 7, 8};
            }
        }
        return exgChannelsCache;
    }

    public int[] getAccelerometerChannels() {
        if (accelChannelsCache == null) {
            try {
                accelChannelsCache = BoardShim.get_accel_channels(BoardIds.CYTON_BOARD.get_code());
            } catch (Exception e) {
                accelChannelsCache = new int[0];
            }
        }
        return accelChannelsCache;
    }

    @Override
    public int getTimestampChannel() {
        if (timestampChannelCache < 0) {
            try {
                timestampChannelCache = BoardShim.get_timestamp_channel(BoardIds.CYTON_BOARD.get_code());
            } catch (Exception e) {
                timestampChannelCache = 22;
            }
        }
        return timestampChannelCache;
    }

    @Override
    public int getSampleIndexChannel() {
        if (sampleIndexChannelCache < 0) {
            try {
                sampleIndexChannelCache = BoardShim.get_package_num_channel(BoardIds.CYTON_BOARD.get_code());
            } catch (Exception e) {
                sampleIndexChannelCache = 0;
            }
        }
        return sampleIndexChannelCache;
    }

    @Override
    public int getMarkerChannel() {
        if (markerChannelCache < 0) {
            try {
                markerChannelCache = BoardShim.get_marker_channel(BoardIds.CYTON_BOARD.get_code());
            } catch (Exception e) {
                markerChannelCache = getTotalChannelCount() - 1;
            }
        }
        return markerChannelCache;
    }

    @Override
    public int getTotalChannelCount() {
        if (totalChannelsCache < 0) {
            try {
                totalChannelsCache = BoardShim.get_num_rows(BoardIds.CYTON_BOARD.get_code());
            } catch (Exception e) {
                totalChannelsCache = 24;
            }
        }
        return totalChannelsCache;
    }

    @Override
    public void setEXGChannelActive(int channelIndex, boolean active) {
        if (channelIndex >= 0 && channelIndex < channelActive.length) {
            channelActive[channelIndex] = active;
        }
    }

    @Override
    public boolean isEXGChannelActive(int channelIndex) {
        if (channelIndex >= 0 && channelIndex < channelActive.length) {
            return channelActive[channelIndex];
        }
        return false;
    }

    @Override
    public Pair<Boolean, String> sendCommand(String command) {
        return new ImmutablePair<Boolean, String>(Boolean.valueOf(false), "Neuro11 UDP source does not support board commands.");
    }

    @Override
    public void insertMarker(int marker) {
        // Marker insertion is not supported in this UDP source.
    }

    @Override
    public void insertMarker(double value) {
        // Marker insertion is not supported in this UDP source.
    }

    @Override
    protected void addChannelNamesInternal(String[] channelNames) {
        // Keep default CYTON-style names from channel index mapping.
    }

    @Override
    protected PacketLossTracker setupPacketLossTracker() {
        final int minSampleIndex = 0;
        final int maxSampleIndex = 255;
        return new PacketLossTracker(getSampleIndexChannel(), getTimestampChannel(),
            minSampleIndex, maxSampleIndex);
    }
}
