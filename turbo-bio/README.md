# turbo-bio-dubu

React Native TurboModule for biometric authentication (TouchID, FaceID, and Android Biometrics).

## Installation

```bash
npm install turbo-bio-dubu
# or
yarn add turbo-bio-dubu
```

### iOS

Add the following to your `Podfile`:

```ruby
pod 'turbo-bio-dubu', :path => '../node_modules/turbo-bio-dubu'
```

Then run:

```bash
pod install
```

### Android

No additional steps required for Android installation.

## Usage

```typescript
import { TurboBio } from 'turbo-bio';

// Check if biometric authentication is available
const checkBiometrics = async () => {
  try {
    const result = await TurboBio.isSensorAvailable();
    console.log('Biometrics available:', result.available);
    if (result.available) {
      console.log('Biometry type:', result.biometryType);
    } else {
      console.log('Error:', result.error);
    }
  } catch (error) {
    console.error('Error checking biometrics:', error);
  }
};

// Create keys for biometric authentication
const createBiometricKeys = async () => {
  try {
    const result = await TurboBio.createKeys();
    console.log('Public key:', result.publicKey);
    return result.publicKey;
  } catch (error) {
    console.error('Error creating keys:', error);
    return null;
  }
};

// Check if biometric keys exist
const checkBiometricKeysExist = async () => {
  try {
    const result = await TurboBio.biometricKeysExist();
    return result.keysExist;
  } catch (error) {
    console.error('Error checking keys:', error);
    return false;
  }
};

// Delete biometric keys
const deleteBiometricKeys = async () => {
  try {
    const result = await TurboBio.deleteKeys();
    return result.keysDeleted;
  } catch (error) {
    console.error('Error deleting keys:', error);
    return false;
  }
};

// Create signature with biometric authentication
const createBiometricSignature = async (payload: string) => {
  try {
    const result = await TurboBio.createSignature({
      promptMessage: 'Authenticate to sign data',
      payload,
      cancelButtonText: 'Cancel'
    });
    
    if (result.success) {
      return result.signature;
    } else {
      console.log('User cancelled or failed authentication');
      return null;
    }
  } catch (error) {
    console.error('Error creating signature:', error);
    return null;
  }
};

// Simple biometric prompt
const simpleBiometricPrompt = async () => {
  try {
    const result = await TurboBio.simplePrompt({
      promptMessage: 'Authenticate to continue',
      cancelButtonText: 'Cancel'
    });
    
    return result.success;
  } catch (error) {
    console.error('Error with biometric prompt:', error);
    return false;
  }
};
```

## API

### `isSensorAvailable()`
Checks if biometric authentication is available.

### `createKeys()`
Creates cryptographic keys for biometric authentication.

### `biometricKeysExist()`
Checks if biometric keys exist.

### `deleteKeys()`
Deletes biometric keys.

### `createSignature(options)`
Creates a signature with biometric authentication.

| Parameter | Type | Description |
|-----------|------|-------------|
| options.promptMessage | string | Message to display in the biometric prompt |
| options.payload | string | Data to sign |
| options.cancelButtonText | string | (Optional) Text for cancel button |

### `simplePrompt(options)`
Displays a simple biometric prompt.

| Parameter | Type | Description |
|-----------|------|-------------|
| options.promptMessage | string | Message to display in the biometric prompt |
| options.cancelButtonText | string | (Optional) Text for cancel button |

## License

MIT