#
# SPDX-FileCopyrightText: Copyright (c) 2021-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

import os
import time
import secrets
import string
from datetime import datetime, timezone, timedelta
from urllib import request
from urllib.error import HTTPError
import json
import base64


from OpenSSL import crypto
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.hashes import SHA384
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.exceptions import InvalidSignature
from cryptography.x509 import ocsp, OCSPNonce
from cryptography import x509

from verifier.attestation import AttestationReport
from verifier.config import (
    BaseSettings,
    info_log,
    event_log,
)
from verifier.utils import (
    format_vbios_version,
    function_wrapper_with_timeout,
)
from verifier.exceptions import (
    NoCertificateError,
    IncorrectNumberOfCertificatesError,
    NonceMismatchError,
    DriverVersionMismatchError,
    SignatureVerificationError,
    VBIOSVersionMismatchError,
    RIMFetchError,
    OCSPFetchError,
    InvalidNonceError
)

class CcAdminUtils:
    """ A class to provide the required functionalities for the CC ADMIN to perform the GPU attestation.
    """
    @staticmethod
    def extract_fwid(cert):
        """ A static function to extract the FWID data from the given certificate.
        Args:
            cert (OpenSSL.crypto.X509): The certificate whose FWID data is needed to be fetched.
        Returns:
            [str]: the FWID as a hex string extracted from the certificate if
                    it is present otherwise returns an empty string.
        """
        result = ''
        # The OID for the FWID extension.
        TCG_DICE_FWID_OID = '2.23.133.5.4.1'
        cryptography_cert = cert.to_cryptography()

        for i in range(len(cryptography_cert.extensions)):
            oid_obj = (vars(cryptography_cert.extensions)['_extensions'][i]).oid
            if getattr(oid_obj, 'dotted_string') == TCG_DICE_FWID_OID:
                # The FWID data is the last 48 bytes.
                result = vars((vars(cryptography_cert.extensions)['_extensions'][i]).value)['_value'][-48:].hex()

        return result

    @staticmethod
    def verify_gpu_certificate_chain(cert_chain, settings, attestation_report_fwid):
        """ A static function to perform the GPU device certificate chain verification.
        Args:
            cert_chain (list): A list containing the certificate objects of the device certificate chain.
            settings (config.HopperSettings): the object containing the various config info.
            attestation_report_fwid (str): the hexadecimal string of the FWID in the attestation report.
        Returns:
            [bool]: True if the verification is successful, otherwise False.
        """
        # Skipping the comparision of FWID in the attestation certificate if the Attestation report does not contains the FWID.
        if attestation_report_fwid != '':

            if attestation_report_fwid != CcAdminUtils.extract_fwid(cert_chain[0]):
                info_log.error("\t\tThe firmware ID in the device certificate chain is not matching with the one in the attestation report.")
                event_log.info(f"\t\tThe FWID read from the attestation report is : {attestation_report_fwid}")
                return False

            info_log.info("\t\tThe firmware ID in the device certificate chain is matching with the one in the attestation report.")

        return CcAdminUtils.verify_certificate_chain(cert_chain, settings, BaseSettings.Certificate_Chain_Verification_Mode.GPU_ATTESTATION)

    @staticmethod
    def verify_certificate_chain(cert_chain, settings, mode):
        """ Performs the certificate chain verification.

        Args:
            cert_chain (list): the certificate chain as a list with the root
                               cert at the end of the list.
            settings (config.HopperSettings): the object containing the various config info.
            mode (<enum 'CERT CHAIN VERIFICATION MODE'>): Used to determine if the certificate chain
                            verification is for the GPU attestation certificate chain or RIM certificate chain
                            or the ocsp response certificate chain.

        Raises:
            NoCertificateError: it is raised if the cert_chain list is empty.
            IncorrectNumberOfCertificatesError: it is raised if the number of
                                certificates in cert_chain list is unexpected.

        Returns:
            [bool]: True if the verification is successful, otherwise False.
        """
        assert isinstance(cert_chain, list)

        number_of_certificates = len(cert_chain)

        event_log.debug(f"verify_certificate_chain() called for {str(mode)}")
        event_log.debug(f'Number of certificates : {number_of_certificates}')

        if number_of_certificates < 1:
            event_log.error("\t\tNo certificates found in certificate chain.")
            raise NoCertificateError("\t\tNo certificates found in certificate chain.")

        if number_of_certificates != settings.MAX_CERT_CHAIN_LENGTH and mode == BaseSettings.Certificate_Chain_Verification_Mode.GPU_ATTESTATION:
            event_log.error("\t\tThe number of certificates fetched from the GPU is unexpected.")
            raise IncorrectNumberOfCertificatesError("\t\tThe number of certificates fetched from the GPU is unexpected.")

        store = crypto.X509Store()
        index = number_of_certificates - 1
        while index > -1:
            if index == number_of_certificates - 1:
                # The root CA certificate is stored at the end in the cert chain.
                store.add_cert(cert_chain[index])
                index = index - 1
            else:
                store_context = crypto.X509StoreContext(store, cert_chain[index])
                try:
                    store_context.verify_certificate()
                    store.add_cert(cert_chain[index])
                    index = index - 1
                except crypto.X509StoreContextError as e:
                    event_log.info(f'Cert chain verification is failing at index : {index}')
                    event_log.error(e)
                    return False
        return True

    @staticmethod
    def convert_cert_from_cryptography_to_pyopenssl(cert):
        """ A static method to convert the "Cryptography" X509 certificate object to "pyOpenSSL"
        X509 certificate object.

        Args:
            cert (cryptography.hazmat.backends.openssl.x509._Certificate): the input certificate object.

        Returns:
            [OpenSSL.crypto.X509]: the converted X509 certificate object.
        """
        return crypto.load_certificate(type=crypto.FILETYPE_ASN1, buffer = cert.public_bytes(serialization.Encoding.DER))

    @staticmethod
    def build_ocsp_request(cert, issuer, nonce=None):
        """ A static method to build the ocsp request message.

        Args:
            cert (OpenSSL.crypto.X509): the input certificate object.
            issuer (OpenSSL.crypto.X509): the issuer certificate object.
            nonce (bytes, optional): the nonce to be added in the ocsp request message. Defaults to None.

        Returns:
            [bytes]: the raw ocsp request message.
        """
        request_builder = ocsp.OCSPRequestBuilder()
        request_builder = request_builder.add_certificate(cert, issuer, SHA384())
        if nonce is not None:
            request_builder = request_builder.add_extension(extval=OCSPNonce(nonce), critical=True)
        return request_builder.build()

    @staticmethod
    def ocsp_certificate_chain_validation(cert_chain, settings, mode):
        """ A static method to perform the ocsp status check of the input certificate chain along with the
        signature verification and the cert chain verification if the ocsp response message received.

        Args:
            cert_chain (list): the list of the input certificates of the certificate chain.
            settings (config.HopperSettings): the object containing the various config info.
            mode (<enum 'CERT CHAIN VERIFICATION MODE'>): Used to determine if the certificate chain
                            verification is for the GPU attestation certificate chain or RIM certificate chain
                            or the ocsp response certificate chain.

        Returns:
            [Bool]: True if the ocsp status of all the appropriate certificates in the
                    certificate chain, otherwise False.
        """
        assert isinstance(cert_chain, list)
        revoked_status = False
        start_index = 0
        gpu_attestation_warning_msg_list = []

        if mode == BaseSettings.Certificate_Chain_Verification_Mode.GPU_ATTESTATION:
            start_index = 1

        end_index = len(cert_chain) - 1

        for i, cert in enumerate(cert_chain):
            cert_chain[i] = cert.to_cryptography()

        for i in range(start_index, end_index):
            cert_common_name = cert_chain[i].subject.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)[0].value

            # Fetch OCSP Response from provided OCSP Service
            nonce = (
                CcAdminUtils.generate_nonce(BaseSettings.SIZE_OF_NONCE_IN_BYTES)
                if BaseSettings.OCSP_NONCE_ENABLED
                else None
            )
            ocsp_request = CcAdminUtils.build_ocsp_request(cert_chain[i], cert_chain[i + 1], nonce)
            try:
                ocsp_response = function_wrapper_with_timeout(
                    [
                        CcAdminUtils.fetch_ocsp_response_from_url,
                        ocsp_request.public_bytes(serialization.Encoding.DER),
                        BaseSettings.OCSP_URL,
                        BaseSettings.OCSP_RETRY_COUNT,
                        "send_ocsp_request",
                    ],
                    BaseSettings.MAX_OCSP_REQUEST_TIME_DELAY * BaseSettings.OCSP_RETRY_COUNT,
                )
            except Exception as e:
                event_log.error(f"Exception occurred while fetching OCSP response from provided OCSP service: {str(e)}")
                ocsp_response = None

            # Fallback to Nvidia OCSP Service if the fetch fails
            if ocsp_response is None:
                nonce = CcAdminUtils.generate_nonce(BaseSettings.SIZE_OF_NONCE_IN_BYTES)
                ocsp_request = CcAdminUtils.build_ocsp_request(cert_chain[i], cert_chain[i + 1], nonce)
                try:
                    ocsp_response = function_wrapper_with_timeout(
                        [
                            CcAdminUtils.fetch_ocsp_response_from_url,
                            ocsp_request.public_bytes(serialization.Encoding.DER),
                            BaseSettings.OCSP_URL_NVIDIA,
                            BaseSettings.OCSP_RETRY_COUNT,
                            "send_ocsp_request",
                        ],
                        BaseSettings.MAX_OCSP_REQUEST_TIME_DELAY * BaseSettings.OCSP_RETRY_COUNT,
                    )
                except Exception as e:
                    event_log.error(f"Exception occurred while fetching OCSP response from Nvidia OCSP service: {str(e)}")
                    ocsp_response = None

            # Raise error if OCSP response is not fetched from both OCSP services
            if ocsp_response is None:
                error_msg = f"Failed to fetch the ocsp response for certificate {cert_common_name}"
                info_log.error(f"\t\t\t{error_msg}")
                raise OCSPFetchError(error_msg)

            # Verify the OCSP response status
            if ocsp_response.response_status != ocsp.OCSPResponseStatus.SUCCESSFUL:
                error_msg = "Couldn't receive a proper response from the OCSP server."
                info_log.error(f"\t\t{error_msg}")
                return False, error_msg

            # Verify the Nonce in the OCSP response
            if nonce is not None and nonce != ocsp_response.extensions.get_extension_for_class(OCSPNonce).value.nonce:
                error_msg = "The nonce in the OCSP response message is not matching with the one passed in the OCSP request message."
                info_log.error(f"\t\t{error_msg}")
                return False, error_msg
            elif i == end_index - 1:
                info_log.debug("\t\tGPU Certificate OCSP Nonce is matching")

            # Verify the OCSP response is within the validity period
            timestamp_format = "%Y/%m/%d %H:%M:%S UTC"
            this_update = ocsp_response.this_update_utc
            next_update = ocsp_response.next_update_utc
            next_update_extended = next_update + timedelta(hours=BaseSettings.OCSP_VALIDITY_EXTENSION_HRS)
            utc_now = datetime.now(timezone.utc)
            event_log.debug(f"Current time: {utc_now.strftime(timestamp_format)}")
            event_log.debug(f"OCSP this update: {this_update.strftime(timestamp_format)}")
            event_log.debug(f"OCSP next update: {next_update.strftime(timestamp_format)}")
            event_log.debug(f"OCSP next update extended: {next_update_extended.strftime(timestamp_format)}")

            # Outside validity period, print warning
            if not (this_update <= utc_now <= next_update):
                ocsp_outside_validity_msg = f"OCSP FOR {cert_common_name} IS EXPIRED AFTER {next_update.strftime(timestamp_format)}."
                event_log.warning(ocsp_outside_validity_msg)
                gpu_attestation_warning_msg_list.append(ocsp_outside_validity_msg)

            # Outside extended validity period
            if not (this_update <= utc_now <= next_update_extended):
                ocsp_outside_extended_validity_msg = (
                    f"OCSP FOR {cert_common_name} IS EXPIRED AND IS NO LONGER VALID FOR ATTESTATION "
                    f"AFTER {next_update_extended.strftime(timestamp_format)}."
                )
                event_log.error(ocsp_outside_extended_validity_msg)
                info_log.error(f"\t\tERROR: {ocsp_outside_extended_validity_msg}")
                return False, ocsp_outside_extended_validity_msg

            # Verifying the ocsp response certificate chain.
            ocsp_response_leaf_cert = crypto.load_certificate(
                type=crypto.FILETYPE_ASN1,
                buffer=ocsp_response.certificates[0].public_bytes(serialization.Encoding.DER),
            )
            ocsp_cert_chain = [ocsp_response_leaf_cert]

            for j in range(i, len(cert_chain)):
                ocsp_cert_chain.append(CcAdminUtils.convert_cert_from_cryptography_to_pyopenssl(cert_chain[j]))
            ocsp_cert_chain_verification_status = CcAdminUtils.verify_certificate_chain(
                ocsp_cert_chain, settings, BaseSettings.Certificate_Chain_Verification_Mode.OCSP_RESPONSE
            )

            if not ocsp_cert_chain_verification_status:
                error_msg = f"The ocsp response certificate chain verification failed for {cert_common_name}."
                info_log.error(f"\t\t{error_msg}")
                return False, error_msg
            elif i == end_index - 1:
                info_log.debug("\t\tGPU Certificate OCSP Cert chain is verified")

            # Verifying the signature of the ocsp response message.
            if not CcAdminUtils.verify_ocsp_signature(ocsp_response):
                error_msg = f"The ocsp response response for certificate {cert_common_name} failed due to signature verification failure."
                info_log.error(f"\t\t{error_msg}")
                return False, error_msg
            elif i == end_index - 1:
                info_log.debug("\t\tGPU Certificate OCSP Signature is verified")

            # The OCSP response certificate status is unknown
            if ocsp_response.certificate_status == ocsp.OCSPCertStatus.UNKNOWN:
                error_msg = f"The {cert_common_name} certificate revocation status is UNKNOWN"
                info_log.error(f"\t\t\t{error_msg}")
                return False, error_msg

            # The OCSP response certificate status is revoked
            if ocsp_response.certificate_status == ocsp.OCSPCertStatus.REVOKED:
                # Get cert revoke timestamp
                cert_revocation_extension_hrs = 0
                if mode == BaseSettings.Certificate_Chain_Verification_Mode.GPU_ATTESTATION:
                    cert_revocation_extension_hrs = BaseSettings.OCSP_CERT_REVOCATION_DEVICE_EXTENSION_HRS
                elif mode == BaseSettings.Certificate_Chain_Verification_Mode.DRIVER_RIM_CERT:
                    cert_revocation_extension_hrs = BaseSettings.OCSP_CERT_REVOCATION_DRIVER_RIM_EXTENSION_HRS
                elif mode == BaseSettings.Certificate_Chain_Verification_Mode.VBIOS_RIM_CERT:
                    cert_revocation_extension_hrs = BaseSettings.OCSP_CERT_REVOCATION_VBIOS_RIM_EXTENSION_HRS

                cert_revocation_time = ocsp_response.revocation_time_utc
                cert_revocation_reason = ocsp_response.revocation_reason
                cert_revocation_time_extended = cert_revocation_time + timedelta(hours=cert_revocation_extension_hrs)

                # Cert is revoked, print warning
                cert_revocation_msg = (
                    f"THE CERTIFICATE {cert_common_name} IS REVOKED FOR '{cert_revocation_reason.value}' "
                    f"AT {cert_revocation_time.strftime(timestamp_format)}."
                )
                event_log.warning(cert_revocation_msg)
                gpu_attestation_warning_msg_list.append(cert_revocation_msg)

                # Cert is revoked but certificate_hold is allowed
                if x509.ReasonFlags.certificate_hold == cert_revocation_reason and BaseSettings.allow_hold_cert:
                    cert_revocation_hold_allowed_msg = (
                        f"THE CERTIFICATE {cert_common_name} IS REVOKED FOR '{cert_revocation_reason.value}' "
                        f"BUT STILL GOOD FOR ATTESTATION WITH allow_hold_cert ENABLED."
                    )
                    event_log.warning(cert_revocation_hold_allowed_msg)
                    gpu_attestation_warning_msg_list.append(cert_revocation_hold_allowed_msg)

                # Cert is revoked but within the extension period
                elif datetime.now(timezone.utc) <= cert_revocation_time_extended:
                    cert_revocation_within_extension_msg = (
                        f"THE CERTIFICATE {cert_common_name} IS REVOKED FOR '{cert_revocation_reason.value}' "
                        f"BUT STILL GOOD FOR ATTESTATION UNTIL {cert_revocation_time_extended.strftime(timestamp_format)} WITH "
                        f"{cert_revocation_extension_hrs} HOURS OF GRACE PERIOD."
                    )
                    event_log.warning(cert_revocation_within_extension_msg)
                    gpu_attestation_warning_msg_list.append(cert_revocation_within_extension_msg)

                # Cert is revoked and outside the extension period
                else:
                    cert_revocation_novalid_msg = (
                        f"THE CERTIFICATE {cert_common_name} IS REVOKED FOR '{cert_revocation_reason.value}' "
                        f"AND NO LONGER GOOD FOR ATTESTATION AFTER {cert_revocation_time_extended.strftime(timestamp_format)}."
                    )
                    event_log.error(cert_revocation_novalid_msg)
                    gpu_attestation_warning_msg_list.append(cert_revocation_novalid_msg)
                    info_log.error(f"\t\t\tERROR: {cert_revocation_novalid_msg}")
                    info_log.error("\t\t\tThe certificate chain revocation status verification was not successful")
                    return False, '\n'.join(gpu_attestation_warning_msg_list)

        info_log.info(f"\t\t\tThe certificate chain revocation status verification successful.")
        return True, '\n'.join(gpu_attestation_warning_msg_list)

    @staticmethod
    def fetch_ocsp_response_from_url(ocsp_request_data, url, max_retries):
        """ A static method to prepare http request and send it to the ocsp server
            and returns the ocsp response message.

        Args:
            ocsp_request_data (bytes): the raw ocsp request message.
            url (str): the url of the ocsp service.
            max_retries (int, optional): the maximum number of retries to be performed in case of any error.

        Returns:
            [cryptography.hazmat.backends.openssl.ocsp._OCSPResponse]: the ocsp response message object.
        """
        # OCSP service URL should start with https
        if not url.lower().startswith("https"):
            info_log.error(f"The OCSP service url {url} does not start with https")
            return None

        # Sending the ocsp request to the given url
        try:
            ocsp_request = request.Request(url, ocsp_request_data)
            ocsp_request.add_header("Content-Type", "application/ocsp-request")

            with request.urlopen(ocsp_request) as ocsp_response_data:
                ocsp_response = ocsp.load_der_ocsp_response(ocsp_response_data.read())
                event_log.debug(f"Successfully fetched the ocsp response from {url}")
                return ocsp_response

        except Exception as e:
            event_log.error(f"Error while fetching the ocsp response from {url}")
            if isinstance(e, HTTPError):
                event_log.error(f"HTTP Error code : {e.code}")
            if max_retries > 0:
                time.sleep(BaseSettings.OCSP_RETRY_DELAY)
                return CcAdminUtils.fetch_ocsp_response_from_url(ocsp_request_data, url, max_retries - 1)
            else:
                return None

    @staticmethod
    def verify_ocsp_signature(ocsp_response):
        """ A static method to perform the signature verification of the ocsp response message.

        Args:
            ocsp_response (cryptography.hazmat.backends.openssl.ocsp._OCSPResponse): the input ocsp response message object.

        Returns:
            [Bool]: returns True if the signature verification is successful, otherwise returns False.
        """
        try:
            signature = ocsp_response.signature
            data = ocsp_response.tbs_response_bytes
            leaf_certificate = ocsp_response.certificates[0]
            leaf_certificate.public_key().verify(signature, data, ec.ECDSA(SHA384()))
            return True

        except InvalidSignature:
            return False

        except Exception as error:
            err_msg = "Something went wrong during ocsp signature verification."
            info_log.error(error)
            info_log.info(err_msg)
            return False

    @staticmethod
    def fetch_rim_file_from_url(rim_id, url, max_retries):
        """ A static method to fetch the RIM file with the given file id from the given url.
            If the fetch fails, it retries for the maximum number of times specified by the max_retries parameter.
            If the max_retries is set to 0, it does not retry on failure and return None.

        Args:
            rim_id (str): the RIM file id which need to be fetched from the given url.
            url (str): the url from which the RIM file needs to be fetched.
            max_retries (int, optional): the maximum number of retries to be performed in case of any error.

        Returns:
            [str]: the content of the required RIM file as a string.
        """
        # RIM service URL should start with https
        if not url.lower().startswith("https"):
            info_log.error(f"The RIM service url {url} does not start with https")
            return None

        # Fetching the RIM file from the given url
        try:
            with request.urlopen(url + rim_id) as https_response:
                data = https_response.read()
                json_object = json.loads(data)
                base64_data = json_object["rim"]
                decoded_str = base64.b64decode(base64_data).decode("utf-8")
                event_log.debug(f"Successfully fetched the RIM file from {url + rim_id}")
                return decoded_str
        except Exception as e:
            event_log.error(f"Error while fetching the RIM file from {url + rim_id}")
            if isinstance(e, HTTPError):
                event_log.error(f"HTTP Error code : {e.code}")
            if max_retries > 0:
                time.sleep(BaseSettings.RIM_SERVICE_RETRY_DELAY)
                return CcAdminUtils.fetch_rim_file_from_url(rim_id, url, max_retries - 1)
            else:
                return None

    @staticmethod
    def fetch_rim_file(rim_id, max_retries=BaseSettings.RIM_SERVICE_RETRY_COUNT):
        """A static method to fetch the RIM file with the given file id from the RIM service.
            It tries to fetch the RIM file from provided RIM service, and fallback to the Nvidia RIM service if the fetch fails.

        Args:
            rim_id (str): the RIM file id which need to be fetched from the RIM service.

        Raises:
            RIMFetchError: it is raised in case the RIM fetch is failed.

        Returns:
            [str]: the content of the required RIM file as a string.
        """
        # Fetching the RIM file from the provided RIM service
        try:
            rim_result = function_wrapper_with_timeout(
                [
                    CcAdminUtils.fetch_rim_file_from_url,
                    rim_id,
                    BaseSettings.RIM_SERVICE_BASE_URL,
                    max_retries,
                    "fetch_rim_file_from_url",
                ],
                BaseSettings.MAX_RIM_REQUEST_TIME_DELAY * max_retries,
            )
        except Exception as e:
            event_log.error(f"Exception occurred while fetching RIM {rim_id} from provided RIM service: {str(e)}")
            rim_result = None

        # RIM is successfully fetched from the provided RIM service
        if rim_result is not None:
            return rim_result

        # Log error if RIM file is not fetched from the provided RIM service
        event_log.error(f"Failed to fetch RIM {rim_id} from provided RIM service: {BaseSettings.RIM_SERVICE_BASE_URL}")

        # Fallback to the Nvidia RIM service if the fetch fails
        if BaseSettings.RIM_SERVICE_BASE_URL_NVIDIA != BaseSettings.RIM_SERVICE_BASE_URL:
            event_log.info(f"Falling back to Nvidia RIM service {BaseSettings.RIM_SERVICE_BASE_URL_NVIDIA}")
            try:
                rim_result = function_wrapper_with_timeout(
                    [
                        CcAdminUtils.fetch_rim_file_from_url,
                        rim_id,
                        BaseSettings.RIM_SERVICE_BASE_URL_NVIDIA,
                        max_retries,
                        "fetch_rim_file_from_url",
                    ],
                    BaseSettings.MAX_RIM_REQUEST_TIME_DELAY * max_retries,
                )
            except Exception as e:
                event_log.error(f"Exception occurred while fetching RIM {rim_id} from Nvidia RIM service: {str(e)}")
                rim_result = None

            # RIM is successfully fetched from the Nvidia RIM service
            if rim_result is not None:
                return rim_result

            # Log error if RIM file is not fetched from the Nvidia RIM service
            event_log.error(f"Failed to fetch RIM {rim_id} from Nvidia RIM service: {BaseSettings.RIM_SERVICE_BASE_URL_NVIDIA}")

        # Raise error if RIM file is not fetched from both the RIM services
        raise RIMFetchError(f"Could not fetch the required RIM file : {rim_id} from the RIM service.")

    @staticmethod
    def get_vbios_rim_file_id(project, project_sku, chip_sku, vbios_version):
        """ A static method to generate the required VBIOS RIM file id which needs to be fetched from the RIM service
            according to the vbios flashed onto the system.

        Args:
            attestation_report (AttestationReport): the object representing the attestation report.

        Returns:
            [str]: the VBIOS RIM file id.
        """
        base_str = 'NV_GPU_VBIOS_'

        return base_str + project + "_" + project_sku + "_" + chip_sku + "_" + vbios_version

    @staticmethod
    def get_driver_rim_file_id(driver_version):
        """ A static method to generate the driver RIM file id to be fetched from the RIM service corresponding to
            the driver installed onto the system.

        Args:
            driver_version (str): the driver version of the installed driver.

        Returns:
            [str]: the driver RIM file id.
        """
        base_str = 'NV_GPU_DRIVER_GH100_'
        return base_str + driver_version

    @staticmethod
    def get_vbios_rim_path(settings, attestation_report):
        """ A static method to determine the path of the appropriate VBIOS RIM file.

        Args:
            settings (config.HopperSettings): the object containing the various config info.
            attestation_report (AttestationReport): the object representing the attestation report

        Raises:
            RIMFetchError: it is raised in case the required VBIOS RIM file is not found.

        Returns:
            [str] : the path to the VBIOS RIM file.
        """
        project = attestation_report.get_response_message().get_opaque_data().get_data("OPAQUE_FIELD_ID_PROJECT")
        project_sku = attestation_report.get_response_message().get_opaque_data().get_data("OPAQUE_FIELD_ID_PROJECT_SKU")
        chip_sku = attestation_report.get_response_message().get_opaque_data().get_data("OPAQUE_FIELD_ID_CHIP_SKU")
        vbios_version = format_vbios_version(attestation_report.get_response_message().get_opaque_data().get_data("OPAQUE_FIELD_ID_VBIOS_VERSION"))
        vbios_version = vbios_version.replace(".", "").upper()

        project = project.decode('ascii').strip().strip('\x00')
        project = project.lower()
        project_sku = project_sku.decode('ascii').strip().strip('\x00')
        project_sku = project_sku.lower()
        chip_sku = chip_sku.decode('ascii').strip().strip('\x00')
        chip_sku = chip_sku.lower()

        rim_file_name = project + "_" + project_sku + "_" + chip_sku + "_" + vbios_version + "_" + settings.get_sku() + ".swidtag"
        list_of_files = os.listdir(settings.RIM_DIRECTORY_PATH)
        rim_path = os.path.join(settings.RIM_DIRECTORY_PATH, rim_file_name)

        if rim_file_name in list_of_files:
            return rim_path

        raise RIMFetchError(f"Could not find the required VBIOS RIM file : {rim_path}")

    @staticmethod
    def verify_attestation_report(attestation_report_obj, gpu_leaf_certificate, nonce, driver_version,
                                  vbios_version, settings):
        """ Performs the verification of the attestation report. This contains matching the nonce in the attestation report with
        the one generated by the cc admin, matching the driver version and vbios version in the attestation report with the one
        fetched from the driver. And then performing the signature verification of the attestation report.

        Args:
            attestation_report_obj (SpdmMeasurementResponseMessage): the object representing the attestation report.
            gpu_leaf_certificate (OpenSSL.crypto.X509): the gpu leaf attestation certificate.
            nonce (bytes): the nonce generated by the cc_admin.
            driver_version (str): the driver version fetched from the GPU.
            vbios_version (str): the vbios version fetched from the GPU.
            settings (config.HopperSettings): the object containing the various config info.

        Raises:
            NonceMismatchError: it is raised in case the nonce generated by cc admin does not match with the one in the attestation report.
            DriverVersionMismatchError: it is raised in case of the driver version does not matches with the one in the attestation report.
            VBIOSVersionMismatchError: it is raised in case of the vbios version does not matches with the one in the attestation report.
            SignatureVerificationError: it is raised in case the signature verification of the attestation report fails.

        Returns:
            [bool]: return True if the signature verification is successful.
        """
        assert isinstance(attestation_report_obj, AttestationReport)
        assert isinstance(gpu_leaf_certificate, crypto.X509)
        assert isinstance(nonce, bytes) and len(nonce) == settings.SIZE_OF_NONCE_IN_BYTES

        # Here the attestation report is the concatenated SPDM GET_MEASUREMENTS request with the SPDM GET_MEASUREMENT response message.
        request_nonce = attestation_report_obj.get_request_message().get_nonce()

        if len(nonce) > settings.SIZE_OF_NONCE_IN_BYTES or len(request_nonce) > settings.SIZE_OF_NONCE_IN_BYTES:
            err_msg = "\t\t Length of Nonce is greater than max nonce size allowed."
            event_log.error(err_msg)
            raise InvalidNonceError(err_msg)

        # compare the generated nonce with the nonce of SPDM GET MEASUREMENT request message in the attestation report.
        if request_nonce != nonce:
            err_msg = "\t\tThe nonce in the SPDM GET MEASUREMENT request message is not matching with the generated nonce."
            event_log.error(err_msg)
            raise NonceMismatchError(err_msg)
        else:
            info_log.info("\t\tThe nonce in the SPDM GET MEASUREMENT request message is matching with the generated nonce.")
            settings.mark_nonce_as_matching()

        # Checking driver version.
        driver_version_from_attestation_report = attestation_report_obj.get_response_message().get_opaque_data().get_data("OPAQUE_FIELD_ID_DRIVER_VERSION")
        driver_version_from_attestation_report = driver_version_from_attestation_report.decode()

        if driver_version_from_attestation_report[-1] == '\0':
            driver_version_from_attestation_report = driver_version_from_attestation_report[:-1]

        info_log.info(f'\t\tDriver version fetched from the attestation report : {driver_version_from_attestation_report}')

        if driver_version_from_attestation_report != driver_version:
            err_msg = "\t\tThe driver version in attestation report is not matching with the driver version fetched from the driver."
            event_log.error(err_msg)
            raise DriverVersionMismatchError(err_msg)

        event_log.debug("Driver version in attestation report is matching.")
        settings.mark_attestation_report_driver_version_as_matching()

        # Checking vbios version.
        vbios_version_from_attestation_report = attestation_report_obj.get_response_message().get_opaque_data().get_data("OPAQUE_FIELD_ID_VBIOS_VERSION")
        vbios_version_from_attestation_report = format_vbios_version(vbios_version_from_attestation_report)
        info_log.info(f'\t\tVBIOS version fetched from the attestation report : {vbios_version_from_attestation_report}')

        if vbios_version_from_attestation_report != vbios_version:
            err_msg = "\t\tThe vbios version in attestation report is not matching with the vbios verison fetched from the driver."
            event_log.error(err_msg)
            raise VBIOSVersionMismatchError(err_msg)

        event_log.debug("VBIOS version in attestation report is matching.")
        settings.mark_attestation_report_vbios_version_as_matching()

        # Performing the signature verification.
        attestation_report_verification_status = attestation_report_obj.verify_signature(gpu_leaf_certificate.to_cryptography(),
                                                                                         settings.signature_length,
                                                                                         settings.HashFunction)
        if attestation_report_verification_status:
            info_log.info("\t\tAttestation report signature verification successful.")
            settings.mark_attestation_report_signature_verified()

        else:
            err_msg = "\t\tAttestation report signature verification failed."
            event_log.error(err_msg)
            raise SignatureVerificationError(err_msg)

        return attestation_report_verification_status

    @staticmethod
    def generate_nonce(size):
        """ Generates cryptographically strong nonce to be sent to the SPDM requester via the nvml api for the attestation report.

        Args:
            size (int): the number of random bytes to be generated.

        Returns:
            [bytes]: the bytes of length "size" generated randomly.
        """
        random_bytes = secrets.token_bytes(size)
        return random_bytes

    @staticmethod
    def validate_and_extract_nonce(nonce_hex_string):
        """ Validate and convert Nonce to bytes format

        Args:
            nonce_hex_string (string): 32 Bytes Nonce represented as Hex String

        Returns:
            [bytes]: Nonce represented as Bytes
        """
        if len(nonce_hex_string) == BaseSettings.SIZE_OF_NONCE_IN_HEX_STR and set(nonce_hex_string).issubset(string.hexdigits):
            return bytes.fromhex(nonce_hex_string)
        else :
            raise InvalidNonceError("Invalid Nonce Size. The nonce should be 32 bytes in length represented as Hex String")

    def __init__(self, number_of_gpus):
        """ It is the constructor for the CcAdminUtils.

        Args:
            number_of_gpus (int): The number of the available GPUs.
        """
        self.number_of_gpus = number_of_gpus
