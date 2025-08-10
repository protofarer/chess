#!/usr/bin/env python3
"""
Aseprite ASE to PNG Converter
Converts all .ase files in the /assets directory to PNG format using Aseprite CLI
"""

import os
import subprocess
import sys
from pathlib import Path


def main():
    assets_directory = "./assets"
    
    # Optional: Accept directory as command line argument
    if len(sys.argv) > 1:
        assets_directory = sys.argv[1]
    
    print(f"Converting .ase files in: {assets_directory}")
    print("-" * 50)
    
    success = convert_ase_to_png(assets_directory)
    
    if success:
        print("All conversions completed successfully!")
        sys.exit(0)
    else:
        print("Some conversions failed. Please check the errors above.")
        sys.exit(1)

def convert_ase_to_png(assets_dir):
    """
    Convert all .ase files in the specified directory to PNG using Aseprite CLI
    
    Args:
        assets_dir (str): Directory containing .ase files (default: "/assets")
    """
    
    # Convert to Path object for easier manipulation
    assets_path = Path(assets_dir)
    
    # Check if the directory exists
    if not assets_path.exists():
        print(f"Error: Directory '{assets_dir}' does not exist.")
        return False
    
    if not assets_path.is_dir():
        print(f"Error: '{assets_dir}' is not a directory.")
        return False
    
    # Find all .ase files in the directory
    ase_files = list(assets_path.glob("*.ase"))
    
    if not ase_files:
        print(f"No .ase files found in '{assets_dir}'")
        return True
    
    print(f"Found {len(ase_files)} .ase file(s) to convert...")
    
    success_count = 0
    error_count = 0
    
    for ase_file in ase_files:
        # Generate output PNG filename (same name, different extension)
        png_file = ase_file.with_suffix('.png')
        
        # Prepare the Aseprite command
        cmd = [
            "aseprite",
            "-b",  # batch mode - don't start UI
            str(ase_file),
            "--save-as",
            str(png_file)
        ]
        
        try:
            print(f"Converting: {ase_file.name} -> {png_file.name}")
            
            # Run the Aseprite command
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )
            
            # Check if the PNG file was created successfully
            if png_file.exists():
                print(f"✓ Successfully converted: {ase_file.name}")
                success_count += 1
            else:
                print(f"✗ Failed to create: {png_file.name}")
                error_count += 1
                
        except subprocess.CalledProcessError as e:
            print(f"✗ Error converting {ase_file.name}:")
            print(f"  Command failed with return code {e.returncode}")
            if e.stderr:
                print(f"  Error output: {e.stderr}")
            error_count += 1
            
        except FileNotFoundError:
            print("✗ Error: 'aseprite.exe' not found in PATH.")
            print("  Make sure Aseprite is installed and added to your system PATH,")
            print("  or modify the script to use the full path to aseprite.exe")
            return False
            
        except Exception as e:
            print(f"✗ Unexpected error converting {ase_file.name}: {e}")
            error_count += 1
    
    # Print summary
    print(f"\nConversion complete!")
    print(f"Successfully converted: {success_count} files")
    if error_count > 0:
        print(f"Failed conversions: {error_count} files")
    
    return error_count == 0

if __name__ == "__main__":
    main()
