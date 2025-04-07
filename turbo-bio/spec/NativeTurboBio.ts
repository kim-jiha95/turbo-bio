import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface BiometryType {
  TOUCH_ID: string;
  FACE_ID: string;
  BIOMETRICS: string;
}

export interface BiometricResult {
  available: boolean;
  biometryType?: string;
  error?: string;
}

export interface CreateSignatureResult {
  success: boolean;
  signature?: string;
  error?: string;
}

export interface KeysResult {
  keysExist: boolean;
}

export interface Spec extends TurboModule {
  isSensorAvailable(): Promise<BiometricResult>;
  createKeys(): Promise<{ publicKey: string }>;
  biometricKeysExist(): Promise<{ keysExist: boolean }>;
  deleteKeys(): Promise<{ keysDeleted: boolean }>;
  createSignature(options: {
    promptMessage: string;
    payload: string;
    cancelButtonText?: string;
  }): Promise<{ success: boolean; signature?: string }>;
  simplePrompt(options: {
    promptMessage: string;
    cancelButtonText?: string;
  }): Promise<{ success: boolean; error?: string }>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TurboBio');
