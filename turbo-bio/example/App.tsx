import React, { useState, useEffect } from 'react';
import { View, Text, Button, StyleSheet, SafeAreaView, ScrollView } from 'react-native';
import { TurboBio } from 'turbo-bio-dubu';

const App = () => {
  const [biometricAvailable, setBiometricAvailable] = useState<boolean | null>(null);
  const [biometricType, setBiometricType] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [keys, setKeys] = useState<boolean>(false);
  const [signatureResult, setSignatureResult] = useState<string | null>(null);

  useEffect(() => {
    checkBiometrics();
  }, []);

  const checkBiometrics = async () => {
    try {
      const result = await TurboBio.isSensorAvailable();
      setBiometricAvailable(result.available);
      if (result.available) {
        setBiometricType(result.biometryType || 'Unknown');
      } else {
        setError(result.error || 'Unknown error');
      }
    } catch (err: any) {
      setError(err.message || 'Failed to check biometrics');
    }
  };

  const createBiometricKeys = async () => {
    try {
      await TurboBio.createKeys();
      checkKeys();
    } catch (err: any) {
      setError(err.message || 'Failed to create keys');
    }
  };

  const checkKeys = async () => {
    try {
      const result = await TurboBio.biometricKeysExist();
      setKeys(result.keysExist);
    } catch (err: any) {
      setError(err.message || 'Failed to check keys');
    }
  };

  const deleteKeys = async () => {
    try {
      await TurboBio.deleteKeys();
      checkKeys();
    } catch (err: any) {
      setError(err.message || 'Failed to delete keys');
    }
  };

  const createSignature = async () => {
    try {
      const payload = 'test-payload-' + Date.now();
      const result = await TurboBio.createSignature({
        promptMessage: 'Sign with biometrics',
        payload,
        cancelButtonText: 'Cancel',
      });
      
      if (result.success) {
        setSignatureResult(result.signature || null);
      } else {
        setError('Signature creation failed or was cancelled');
      }
    } catch (err: any) {
      setError(err.message || 'Failed to create signature');
    }
  };

  const showSimplePrompt = async () => {
    try {
      const result = await TurboBio.simplePrompt({
        promptMessage: 'Authenticate to continue',
        cancelButtonText: 'Cancel',
      });
      
      if (result.success) {
        setError(null);
        alert('Authentication successful!');
      } else {
        setError(result.error || 'Authentication failed');
      }
    } catch (err: any) {
      setError(err.message || 'Authentication error');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContainer}>
        <Text style={styles.title}>TurboBio Demo</Text>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Biometric Status</Text>
          <Text>Available: {biometricAvailable === null ? 'Checking...' : biometricAvailable ? 'Yes' : 'No'}</Text>
          {biometricType && <Text>Type: {biometricType}</Text>}
          {error && <Text style={styles.error}>Error: {error}</Text>}
        </View>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Biometric Keys</Text>
          <Text>Keys Exist: {keys ? 'Yes' : 'No'}</Text>
          <View style={styles.buttonRow}>
            <Button title="Create Keys" onPress={createBiometricKeys} disabled={keys} />
            <View style={styles.buttonSpacer} />
            <Button title="Delete Keys" onPress={deleteKeys} disabled={!keys} />
          </View>
        </View>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Biometric Authentication</Text>
          <Button 
            title="Show Simple Prompt" 
            onPress={showSimplePrompt} 
            disabled={!biometricAvailable}
          />
        </View>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Biometric Signature</Text>
          <Button 
            title="Create Signature" 
            onPress={createSignature} 
            disabled={!keys} 
          />
          {signatureResult && (
            <View style={styles.signatureContainer}>
              <Text style={styles.signatureTitle}>Signature:</Text>
              <Text style={styles.signatureText} numberOfLines={3}>
                {signatureResult}
              </Text>
            </View>
          )}
        </View>
        
        <Button title="Refresh Status" onPress={() => {
          checkBiometrics();
          checkKeys();
        }} />
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContainer: {
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  section: {
    backgroundColor: 'white',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  buttonRow: {
    flexDirection: 'row',
    marginTop: 12,
  },
  buttonSpacer: {
    width: 16,
  },
  error: {
    color: 'red',
    marginTop: 8,
  },
  signatureContainer: {
    marginTop: 12,
    padding: 12,
    backgroundColor: '#f0f0f0',
    borderRadius: 4,
  },
  signatureTitle: {
    fontWeight: 'bold',
    marginBottom: 6,
  },
  signatureText: {
    fontSize: 12,
    fontFamily: 'monospace',
  },
});

export default App;