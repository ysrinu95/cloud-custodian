#!/usr/bin/env python3
"""
cleanup_events_rule.py - Python script to clean up CloudWatch Events rules with targets
This script properly removes targets before deleting the rule to avoid the validation error.

Usage: python cleanup_events_rule.py --rule-name custodian-ebs-unencrypted-volumes-scheduled [options]
"""

import argparse
import boto3
import sys
import time
from botocore.exceptions import ClientError


class EventsRuleCleanup:
    def __init__(self, profile=None, region='us-east-1'):
        """Initialize the cleanup handler."""
        self.profile = profile
        self.region = region
        
        # Create session
        if profile:
            self.session = boto3.Session(profile_name=profile, region_name=region)
        else:
            self.session = boto3.Session(region_name=region)
        
        self.events_client = self.session.client('events')
    
    def print_status(self, message):
        """Print status message."""
        print(f"[INFO] {message}")
    
    def print_success(self, message):
        """Print success message."""
        print(f"[SUCCESS] {message}")
    
    def print_warning(self, message):
        """Print warning message."""
        print(f"[WARNING] {message}")
    
    def print_error(self, message):
        """Print error message."""
        print(f"[ERROR] {message}")
    
    def rule_exists(self, rule_name):
        """Check if the rule exists."""
        try:
            self.print_status(f"Checking if rule '{rule_name}' exists...")
            self.events_client.describe_rule(Name=rule_name)
            self.print_success(f"Rule '{rule_name}' found")
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                self.print_warning(f"Rule '{rule_name}' not found")
                return False
            else:
                self.print_error(f"Error checking rule: {e}")
                return False
    
    def remove_targets(self, rule_name, dry_run=False):
        """Remove all targets from the rule."""
        try:
            self.print_status(f"Listing targets for rule '{rule_name}'...")
            
            # Get targets
            response = self.events_client.list_targets_by_rule(Rule=rule_name)
            targets = response.get('Targets', [])
            
            if not targets:
                self.print_status(f"No targets found for rule '{rule_name}'")
                return True
            
            target_ids = [target['Id'] for target in targets]
            self.print_status(f"Found targets: {', '.join(target_ids)}")
            
            if dry_run:
                self.print_warning(f"DRYRUN: Would remove targets: {', '.join(target_ids)}")
                return True
            
            # Remove targets
            self.print_status(f"Removing targets from rule '{rule_name}'...")
            remove_response = self.events_client.remove_targets(
                Rule=rule_name,
                Ids=target_ids
            )
            
            failed_count = remove_response.get('FailedEntryCount', 0)
            if failed_count > 0:
                self.print_warning(f"Some targets failed to be removed (FailedEntryCount: {failed_count})")
                failed_entries = remove_response.get('FailedEntries', [])
                for entry in failed_entries:
                    self.print_error(f"Failed to remove target {entry.get('TargetId', 'unknown')}: {entry.get('ErrorMessage', 'Unknown error')}")
                return False
            
            self.print_success(f"Successfully removed {len(target_ids)} target(s) from rule '{rule_name}'")
            return True
            
        except ClientError as e:
            self.print_error(f"Error removing targets: {e}")
            return False
    
    def delete_rule(self, rule_name, dry_run=False):
        """Delete the rule."""
        try:
            self.print_status(f"Deleting rule '{rule_name}'...")
            
            if dry_run:
                self.print_warning(f"DRYRUN: Would delete rule '{rule_name}'")
                return True
            
            self.events_client.delete_rule(Name=rule_name)
            self.print_success(f"Successfully deleted rule '{rule_name}'")
            return True
            
        except ClientError as e:
            self.print_error(f"Error deleting rule: {e}")
            return False
    
    def cleanup_rule(self, rule_name, dry_run=False):
        """Main cleanup method."""
        self.print_status("Starting CloudWatch Events rule cleanup...")
        self.print_status(f"Rule: {rule_name}")
        self.print_status(f"Region: {self.region}")
        if self.profile:
            self.print_status(f"Profile: {self.profile}")
        if dry_run:
            self.print_warning("DRYRUN MODE: No changes will be made")
        print()
        
        # Step 1: Check if rule exists
        if not self.rule_exists(rule_name):
            self.print_warning(f"Rule '{rule_name}' does not exist. Nothing to clean up.")
            return True
        
        # Step 2: Remove targets
        if not self.remove_targets(rule_name, dry_run):
            self.print_error("Failed to remove targets. Cannot proceed with rule deletion.")
            return False
        
        # Wait a moment for targets to be fully removed
        if not dry_run:
            self.print_status("Waiting for targets to be fully removed...")
            time.sleep(3)
        
        # Step 3: Delete the rule
        if not self.delete_rule(rule_name, dry_run):
            self.print_error(f"Failed to delete rule '{rule_name}'")
            return False
        
        print()
        self.print_success("✅ CloudWatch Events rule cleanup completed successfully!")
        
        if not dry_run:
            self.print_status(f"Rule '{rule_name}' has been completely removed")
        else:
            self.print_status("DRYRUN completed - no actual changes were made")
        
        return True


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Clean up CloudWatch Events rules that have targets attached"
    )
    parser.add_argument(
        '--rule-name', '-r',
        required=True,
        help="Name of the CloudWatch Events rule to delete"
    )
    parser.add_argument(
        '--profile', '-p',
        help="AWS CLI profile to use"
    )
    parser.add_argument(
        '--region', '-R',
        default='us-east-1',
        help="AWS region (default: us-east-1)"
    )
    parser.add_argument(
        '--dry-run', '-d',
        action='store_true',
        help="Show what would be done without making changes"
    )
    
    args = parser.parse_args()
    
    try:
        cleanup = EventsRuleCleanup(profile=args.profile, region=args.region)
        success = cleanup.cleanup_rule(args.rule_name, dry_run=args.dry_run)
        
        if success:
            sys.exit(0)
        else:
            sys.exit(1)
            
    except Exception as e:
        print(f"[ERROR] Unexpected error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()