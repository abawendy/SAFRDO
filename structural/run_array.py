import serial
import time

COM_PORT = 'COM8' 
BAUD_RATE = 115200

def send_slowly(serial_port, byte_array):
    """Sends bytes one at a time to prevent FPGA UART overrun"""
    for b in byte_array:
        serial_port.write(bytes([b]))
        time.sleep(0.005) # 5 millisecond delay between bytes

def main():
    print(f"Connecting to FPGA on {COM_PORT}...")
    try:
        fpga = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
        time.sleep(1) 
        
        # --- 1. LOAD TABLE A ---
        print("Loading Row into BRAM A...")
        send_slowly(fpga, [0xAA, 0x10, 0x20, 0x30, 0x40])

        # --- 2. LOAD TABLE B (Perfect Match!) ---
        print("Loading Row into BRAM B...")
        send_slowly(fpga, [0xBB, 0x10, 0x20, 0x30, 0x40])

        # --- 3. SEND INSTRUCTION & EXECUTE ---
        print("Sending Execute Command (0xEE) and Instruction (0xFF10)...")
        send_slowly(fpga, [0xEE, 0x10, 0xFF])

        # --- 4. READ THE RESULT ---
        print("Waiting for hardware to process...")
        result_bytes = fpga.read(7)
        
        if len(result_bytes) == 7:
            print("\nSUCCESS! Data received:")
            final_value = int.from_bytes(result_bytes, byteorder='big')
            print(f"50-bit Result: {format(final_value, '050b')}")
        else:
            print(f"\nTimeout! Got {len(result_bytes)} bytes.")

        fpga.close()

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()